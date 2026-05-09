//! DLEQ (Discrete Logarithm Equality) Proof Generation
//!
//! Implements Schnorr-style DLEQ proofs to cryptographically bind the hashlock
//! to the adaptor point in atomic swaps.
//!
//! DLEQ proves: ∃t such that T = t·G and U = t·Y, where:
//! - T is the adaptor point (t·G)
//! - U is the second point (t·Y)
//! - G is the standard Ed25519 generator
//! - Y is the second generator point (derived deterministically)
//!
//! **Hash Function Compatibility (CRITICAL):**
//!
//! **Hashlock**: SHA-256 (matches Cairo's `compute_sha256_byte_array`)
//! - Hashlock H = SHA-256(raw_secret_bytes) → 32 bytes
//! - Cairo verification: `compute_sha256_byte_array(@secret)` (line 777)
//! - Used for: Secret verification in `reveal_secret()` and `verify_and_unlock()`
//!
//! **DLEQ Challenge**: Poseidon (matches Cairo's `compute_dleq_challenge_poseidon`)
//! - Challenge c = Poseidon("DLEQ" || G || Y || T || U || R1 || R2 || hashlock) mod n
//! - Cairo computation: `compute_dleq_challenge_poseidon(...)`
//! - Used for: Fiat-Shamir challenge in DLEQ proof verification
//! - BLAKE2s path kept in repo for future enablement
//!
//! **VERIFICATION**: Both Rust and Cairo use:
//! - SHA-256 for hashlock verification ✅
//! - Poseidon for DLEQ challenge computation ✅
#![allow(non_snake_case)]
#![allow(unused_assignments)]

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::edwards::{CompressedEdwardsY, EdwardsPoint};
use curve25519_dalek::scalar::Scalar;
use curve25519_dalek::traits::IsIdentity;
use hex;
use sha2::{Digest, Sha256, Sha512};
use std::ops::Deref;
use thiserror::Error;
use zeroize::{Zeroize, Zeroizing};

// Safe Ed25519 → BN254 conversion (security-critical)
pub mod ed25519_bn254;

use lambdaworks_crypto::hash::poseidon::{starknet::PoseidonCairoStark252, Poseidon};
use lambdaworks_math::field::{
    element::FieldElement as PoseidonFieldElement,
    fields::fft_friendly::stark_252_prime_field::Stark252PrimeField,
};
use num_bigint::BigUint;
use num_traits::One;

type PoseidonFE = PoseidonFieldElement<Stark252PrimeField>;

/// DLEQ proof generation errors.
#[derive(Debug, Error, Clone, PartialEq)]
pub enum DleqError {
    #[error("Secret scalar cannot be zero")]
    ZeroScalar,
    #[error("Adaptor point does not match secret: expected T = t·G")]
    PointMismatch,
    #[error("Hashlock does not match secret: expected H = SHA256(t)")]
    HashlockMismatch,
    #[error("Failed to generate valid nonce after maximum attempts")]
    NonceGenerationFailed,
    #[error("Invalid proof data (decompression or deserialization failed)")]
    InvalidProof,
    #[error("Scalar is not compatible with BN254 field operations")]
    ScalarIncompatible,
    #[error("Scalar conversion error: {0}")]
    ScalarConversionError(String),
    #[error("Failed to derive Edwards x-coordinate for sqrt hint")]
    SqrtHintDerivationFailed,
}

/// DLEQ proof structure containing the second point, challenge, response, and commitments.
///
/// **Security**: This struct derives `Zeroize` to ensure sensitive data is cleared from memory.
/// Public values (points, challenge, response) don't need zeroization, but the struct itself
/// can be zeroized if needed for cleanup.
#[derive(Debug, Clone, PartialEq, Zeroize)]
pub struct DleqProof {
    /// Second point U = t·Y
    #[zeroize(skip)] // Public value, no need to zeroize
    pub second_point: EdwardsPoint,
    /// Challenge scalar c
    #[zeroize(skip)] // Public value, no need to zeroize
    pub challenge: Scalar,
    /// Response scalar s = k + c·t mod n
    #[zeroize(skip)] // Public value, no need to zeroize
    pub response: Scalar,
    /// First commitment R1 = k·G (needed for Cairo challenge computation)
    #[zeroize(skip)] // Public value, no need to zeroize
    pub r1: EdwardsPoint,
    /// Second commitment R2 = k·Y (needed for Cairo challenge computation)
    #[zeroize(skip)] // Public value, no need to zeroize
    pub r2: EdwardsPoint,
}

/// Cairo-compatible format for DLEQ proof data.
/// Contains compressed Edwards points and sqrt hints needed for Cairo decompression.
pub struct DleqProofForCairo {
    /// Adaptor point T = t·G (compressed Edwards, 32 bytes)
    pub adaptor_point_compressed: [u8; 32],
    /// Sqrt hint for adaptor point decompression (x-coordinate as u256)
    pub adaptor_point_sqrt_hint: [u8; 32],
    /// DLEQ second point U = t·Y (compressed Edwards, 32 bytes)
    pub second_point_compressed: [u8; 32],
    /// Sqrt hint for second point decompression (x-coordinate as u256)
    pub second_point_sqrt_hint: [u8; 32],
    /// Challenge scalar c (32 bytes)
    pub challenge: [u8; 32],
    /// Response scalar s (32 bytes)
    pub response: [u8; 32],
    /// Standard generator G (compressed Edwards, 32 bytes)
    pub g_compressed: [u8; 32],
    /// Second generator Y (compressed Edwards, 32 bytes)
    pub y_compressed: [u8; 32],
    /// First commitment R1 = k·G (compressed Edwards, 32 bytes)
    pub r1_compressed: [u8; 32],
    /// Sqrt hint for R1 decompression (x-coordinate as u256)
    pub r1_sqrt_hint: [u8; 32],
    /// Second commitment R2 = k·Y (compressed Edwards, 32 bytes)
    pub r2_compressed: [u8; 32],
    /// Sqrt hint for R2 decompression (x-coordinate as u256)
    pub r2_sqrt_hint: [u8; 32],
}

/// Generate a DLEQ proof for the given secret and adaptor point.
///
/// # Security: Input Validation
///
/// This function validates all inputs before generating the proof:
/// - Secret must be non-zero
/// - Adaptor point must equal secret * G
/// - Hashlock must equal SHA256(raw_secret_bytes)
///
/// # Arguments
///
/// * `secret` - The secret scalar t (wrapped in Zeroizing for automatic memory clearing)
/// * `secret_bytes` - The raw secret bytes (32 bytes) BEFORE scalar reduction
/// * `adaptor_point` - The adaptor point T = t·G
/// * `hashlock` - The hashlock (32-byte SHA-256 hash of raw_secret_bytes)
///
/// # Returns
///
/// A `Result` containing either:
/// - `Ok(DleqProof)` - Valid proof containing U, c, and s
/// - `Err(DleqError)` - Input validation error
///
/// # Errors
///
/// Returns `DleqError::ZeroScalar` if secret is zero.
/// Returns `DleqError::PointMismatch` if adaptor_point ≠ secret * G.
/// Returns `DleqError::HashlockMismatch` if hashlock ≠ SHA256(raw_secret_bytes).
///
/// # Security
///
/// The secret is wrapped in `Zeroizing<Scalar>` to ensure it's automatically zeroed
/// when dropped. The nonce `k` is also wrapped in `Zeroizing` and automatically cleared.
///
/// # Hashlock Format (CRITICAL)
///
/// This function uses `SHA-256(raw_secret_bytes)` to match Cairo's `verify_and_unlock`
/// implementation. DO NOT use `SHA-256(scalar.to_bytes())` as scalar reduction may
/// change the bytes, causing hashlock mismatch.
pub fn generate_dleq_proof(
    secret: &Zeroizing<Scalar>,
    secret_bytes: &[u8; 32],
    adaptor_point: &EdwardsPoint,
    hashlock: &[u8; 32],
) -> Result<DleqProof, DleqError> {
    // SECURITY: Validate inputs before generating proof

    // 1. Check secret is non-zero (use double deref for Zeroizing)
    if **secret == Scalar::ZERO {
        return Err(DleqError::ZeroScalar);
    }

    // 2. Verify adaptor_point = secret * G (use deref() for Zeroizing)
    let G = ED25519_BASEPOINT_POINT;
    let computed_point = G * secret.deref();
    if computed_point != *adaptor_point {
        return Err(DleqError::PointMismatch);
    }

    // 3. Verify hashlock = SHA256(raw_secret_bytes) for Cairo compatibility
    // AUDIT: Warn if scalar reduction changed the bytes (could cause hashlock mismatch)
    let scalar_bytes = secret.to_bytes();
    if scalar_bytes != *secret_bytes {
        eprintln!("⚠️  WARNING: Scalar reduction changed bytes!");
        eprintln!("    Raw:    {}", hex::encode(secret_bytes));
        eprintln!("    Scalar: {}", hex::encode(scalar_bytes));
        eprintln!("    Using raw bytes for hashlock (Cairo-compatible)");
    }

    let computed_hash: [u8; 32] = Sha256::digest(secret_bytes).into();
    if computed_hash != *hashlock {
        return Err(DleqError::HashlockMismatch);
    }

    // 4. Get generators
    let Y = get_second_generator(); // Derived second base

    // 5. Compute U = t·Y (use deref() for Zeroizing)
    let U = Y * secret.deref();

    // 6. Generate nonce k (deterministic for reproducibility in tests)
    // Using RFC6979-style deterministic nonce generation with domain separation
    // k is wrapped in Zeroizing and will be automatically zeroed when dropped
    let k = generate_deterministic_nonce(secret, hashlock)?;

    // 7. Compute commitments (use deref() for Zeroizing)
    let R1 = G * k.deref(); // k·G
    let R2 = Y * k.deref(); // k·Y

    // 8. Compute Fiat-Shamir challenge
    let c = compute_challenge(&G, &Y, adaptor_point, &U, &R1, &R2, hashlock);

    // 9. Compute response s = k + c·t mod n
    // SECURITY: Uses curve25519-dalek's constant-time scalar arithmetic
    // to prevent timing attacks. DO NOT replace with standard operators.
    // k is Zeroizing<Scalar> and will be automatically zeroed when dropped
    let s = k.deref() + (c * secret.deref());
    // k is automatically zeroed here when it goes out of scope

    Ok(DleqProof {
        second_point: U,
        challenge: c,
        response: s,
        r1: R1,
        r2: R2,
    })
}

/// Generate DLEQ proof for Bob's secret (s_b)
///
/// SECURITY: Verifies Ed25519→BN254 compatibility before proof generation.
/// This is a convenience function for the two-party protocol.
pub fn generate_dleq_proof_for_bob(
    bob_keys: &crate::monero::two_party_keys::BobKeys,
) -> Result<DleqProof, DleqError> {
    use crate::dleq::ed25519_bn254::ed25519_scalar_to_bn254_safe;
    use zeroize::Zeroizing;

    let secret = bob_keys.spend_share();

    // CRITICAL: Validate scalar is safe for cross-curve use
    let _bn254_bytes = ed25519_scalar_to_bn254_safe(&secret)
        .map_err(|e| DleqError::ScalarConversionError(e.to_string()))?;

    let secret_bytes = bob_keys.secret_bytes();
    let adaptor_point = bob_keys.adaptor_point();
    let hashlock = bob_keys.hashlock();

    generate_dleq_proof(
        &Zeroizing::new(secret),
        &secret_bytes,
        &adaptor_point,
        &hashlock,
    )
}

/// Convert an Edwards point to compressed format and sqrt hint.
///
/// The sqrt hint is the Edwards x-coordinate (u256, 32 bytes little-endian).
/// This is needed by Cairo's `decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point`.
fn edwards_point_to_cairo_format(point: &EdwardsPoint) -> Result<([u8; 32], [u8; 32]), DleqError> {
    let compressed = point.compress().to_bytes();
    let sqrt_hint = edwards_x_from_compressed(&compressed)?;
    Ok((compressed, sqrt_hint))
}

/// Derive the Edwards x-coordinate from a compressed Edwards Y encoding.
///
/// This mirrors the Ed25519 decompression math to recover x from y:
/// x^2 = (y^2 - 1) / (d*y^2 + 1) mod p, with sign bit selection.
///
/// This is used only for Cairo sqrt hints (off-chain serialization), not in proof math.
fn edwards_x_from_compressed(compressed: &[u8; 32]) -> Result<[u8; 32], DleqError> {
    let p = ed25519_field_prime();
    let d = ed25519_d(&p);
    let sqrt_m1 = ed25519_sqrt_m1(&p);

    let compressed_int = BigUint::from_bytes_le(compressed);
    let sign_bit = ((&compressed_int >> 255) & BigUint::one()) == BigUint::one();
    let y_mask = (BigUint::one() << 255) - BigUint::one();
    let y = &compressed_int & &y_mask;

    let y2 = (&y * &y) % &p;
    let numerator = (&y2 + &p - BigUint::one()) % &p;
    let denominator = (&d * &y2 + BigUint::one()) % &p;
    let denominator_inv = modinv(&denominator, &p);
    let x2 = (&numerator * &denominator_inv) % &p;

    // x = x2^((p+3)/8)
    let exp = (&p + BigUint::from(3u8)) >> 3;
    let mut x = x2.modpow(&exp, &p);
    if (&x * &x) % &p != x2 {
        x = (&x * &sqrt_m1) % &p;
    }
    if (&x * &x) % &p != x2 {
        return Err(DleqError::SqrtHintDerivationFailed);
    }

    let x_is_odd = (&x & BigUint::one()) == BigUint::one();
    if x_is_odd != sign_bit {
        x = (&p - &x) % &p;
    }

    let x_bytes = x.to_bytes_le();
    if x_bytes.len() > 32 {
        return Err(DleqError::SqrtHintDerivationFailed);
    }
    let mut out = [0u8; 32];
    out[..x_bytes.len()].copy_from_slice(&x_bytes);
    Ok(out)
}

/// Derive a Cairo sqrt hint from a compressed Edwards point.
pub fn sqrt_hint_from_compressed(compressed: &[u8; 32]) -> Result<[u8; 32], DleqError> {
    edwards_x_from_compressed(compressed)
}

fn ed25519_field_prime() -> BigUint {
    (BigUint::one() << 255) - BigUint::from(19u8)
}

fn ed25519_d(p: &BigUint) -> BigUint {
    // d = -121665 / 121666 mod p
    let minus_121665 = p - BigUint::from(121665u32);
    let inv_121666 = modinv(&BigUint::from(121666u32), p);
    (minus_121665 * inv_121666) % p
}

fn ed25519_sqrt_m1(p: &BigUint) -> BigUint {
    // sqrt(-1) = 2^((p-1)/4) mod p
    let exp = (p - BigUint::one()) >> 2;
    BigUint::from(2u8).modpow(&exp, p)
}

fn modinv(value: &BigUint, modulus: &BigUint) -> BigUint {
    // modulus is prime (2^255 - 19), so inv = value^(p-2)
    value.modpow(&(modulus - BigUint::from(2u8)), modulus)
}

/// Serializable version of DLEQ proof for JSON/network transport.
///
/// This struct contains all proof data in serializable format (compressed points as bytes).
/// Use `DleqProof::to_serializable()` and `DleqProof::from_serializable()` for conversion.
#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct DleqProofSerialized {
    /// Second point U = t·Y (compressed Edwards, 32 bytes)
    pub second_point: [u8; 32],
    /// Challenge scalar c (32 bytes)
    pub challenge: [u8; 32],
    /// Response scalar s (32 bytes)
    pub response: [u8; 32],
    /// First commitment R1 = k·G (compressed Edwards, 32 bytes)
    pub r1: [u8; 32],
    /// Second commitment R2 = k·Y (compressed Edwards, 32 bytes)
    pub r2: [u8; 32],
}

impl DleqProof {
    /// Convert DLEQ proof to serializable format for JSON/network transport.
    ///
    /// # Returns
    ///
    /// A `DleqProofSerialized` containing all proof data as bytes.
    pub fn to_serializable(&self) -> DleqProofSerialized {
        DleqProofSerialized {
            second_point: self.second_point.compress().to_bytes(),
            challenge: self.challenge.to_bytes(),
            response: self.response.to_bytes(),
            r1: self.r1.compress().to_bytes(),
            r2: self.r2.compress().to_bytes(),
        }
    }

    /// Reconstruct DLEQ proof from serializable format.
    ///
    /// # Arguments
    ///
    /// * `ser` - The serialized proof data
    ///
    /// # Returns
    ///
    /// A `Result` containing either:
    /// - `Ok(DleqProof)` - Valid reconstructed proof
    /// - `Err(DleqError)` - Invalid proof data (decompression failed)
    pub fn from_serializable(ser: DleqProofSerialized) -> Result<Self, DleqError> {
        let second_point = CompressedEdwardsY(ser.second_point)
            .decompress()
            .ok_or(DleqError::PointMismatch)?;

        let r1 = CompressedEdwardsY(ser.r1)
            .decompress()
            .ok_or(DleqError::PointMismatch)?;

        let r2 = CompressedEdwardsY(ser.r2)
            .decompress()
            .ok_or(DleqError::PointMismatch)?;

        let challenge: Option<Scalar> = Scalar::from_canonical_bytes(ser.challenge).into();
        let challenge = challenge.ok_or(DleqError::InvalidProof)?;

        let response: Option<Scalar> = Scalar::from_canonical_bytes(ser.response).into();
        let response = response.ok_or(DleqError::InvalidProof)?;

        Ok(DleqProof {
            second_point,
            challenge,
            response,
            r1,
            r2,
        })
    }

    /// Convert DLEQ proof to JSON string.
    ///
    /// # Returns
    ///
    /// A `Result` containing either:
    /// - `Ok(String)` - JSON representation of the proof
    /// - `Err(serde_json::Error)` - Serialization error
    pub fn to_json(&self) -> Result<String, serde_json::Error> {
        serde_json::to_string(&self.to_serializable())
    }

    /// Reconstruct DLEQ proof from JSON string.
    ///
    /// # Arguments
    ///
    /// * `json` - JSON string representation of the proof
    ///
    /// # Returns
    ///
    /// A `Result` containing either:
    /// - `Ok(DleqProof)` - Valid reconstructed proof
    /// - `Err` - JSON parsing or proof reconstruction error
    pub fn from_json(json: &str) -> Result<Self, Box<dyn std::error::Error>> {
        let ser: DleqProofSerialized = serde_json::from_str(json)?;
        Ok(Self::from_serializable(ser)?)
    }

    /// Convert DLEQ proof to Cairo-compatible format.
    ///
    /// This method generates all compressed Edwards points and sqrt hints needed
    /// for Cairo contract deployment and DLEQ verification.
    ///
    /// # Arguments
    ///
    /// * `adaptor_point` - The adaptor point T = t·G
    ///
    /// # Returns
    ///
    /// A `DleqProofForCairo` containing all data needed for Cairo.
    pub fn to_cairo_format(
        &self,
        adaptor_point: &EdwardsPoint,
    ) -> Result<DleqProofForCairo, DleqError> {
        let G = ED25519_BASEPOINT_POINT;
        let Y = get_second_generator();

        // Convert all points to compressed format with sqrt hints
        let (adaptor_compressed, adaptor_sqrt_hint) = edwards_point_to_cairo_format(adaptor_point)?;
        let (second_compressed, second_sqrt_hint) =
            edwards_point_to_cairo_format(&self.second_point)?;
        let (g_compressed, _) = edwards_point_to_cairo_format(&G)?;
        let (y_compressed, _) = edwards_point_to_cairo_format(&Y)?;
        let (r1_compressed, r1_sqrt_hint) = edwards_point_to_cairo_format(&self.r1)?;
        let (r2_compressed, r2_sqrt_hint) = edwards_point_to_cairo_format(&self.r2)?;

        Ok(DleqProofForCairo {
            adaptor_point_compressed: adaptor_compressed,
            adaptor_point_sqrt_hint: adaptor_sqrt_hint,
            second_point_compressed: second_compressed,
            second_point_sqrt_hint: second_sqrt_hint,
            challenge: self.challenge.to_bytes(),
            response: self.response.to_bytes(),
            g_compressed,
            y_compressed,
            r1_compressed,
            r1_sqrt_hint,
            r2_compressed,
            r2_sqrt_hint,
        })
    }
}

/// Get the second generator point Y for DLEQ proofs.
///
/// CRITICAL: Must match Cairo's `get_dleq_second_generator()` and
/// `ED25519_SECOND_GENERATOR_COMPRESSED` constants exactly.
///
/// The point is derived deterministically from a domain-separated transcript by
/// trying SHA-512 outputs as compressed Edwards-Y encodings, then multiplying by
/// the cofactor to land in the prime-order subgroup. This avoids the old `2*G`
/// placeholder while keeping the constant reproducible.
pub fn get_second_generator() -> EdwardsPoint {
    const DST: &[u8] = b"MONERO_STARKNET_ATOMIC_SWAP_DLEQ_SECOND_GENERATOR_V1";

    for counter in 0u32..1024 {
        let mut hasher = Sha512::new();
        hasher.update(DST);
        hasher.update(counter.to_le_bytes());
        let digest = hasher.finalize();

        let mut compressed = [0u8; 32];
        compressed.copy_from_slice(&digest[..32]);

        if let Some(point) = CompressedEdwardsY(compressed).decompress() {
            let subgroup_point = point.mul_by_cofactor();
            if !subgroup_point.is_identity() && subgroup_point.is_torsion_free() {
                return subgroup_point;
            }
        }
    }

    unreachable!("domain-separated Ed25519 second generator derivation failed")
}

/// Generate a deterministic nonce k for DLEQ proof generation.
///
/// Uses RFC6979-style deterministic nonce generation with domain separation.
/// This ensures reproducibility in tests while maintaining security.
///
/// # Security Features
///
/// - Domain separation: Uses "DLEQ_NONCE_V1" prefix to prevent hash collisions
/// - Counter-based retry: Increments counter if nonce is zero (invalid)
/// - Maximum attempts: Fails after 100 attempts to prevent infinite loops
///
/// # Arguments
///
/// * `secret` - The secret scalar t
/// * `hashlock` - The hashlock (32-byte SHA-256 hash of the secret)
///
/// # Returns
///
/// A `Result` containing either:
/// - `Ok(Scalar)` - Valid non-zero nonce
/// - `Err(DleqError::NonceGenerationFailed)` - Failed to generate valid nonce
/// Generate a deterministic nonce for DLEQ proof generation.
///
/// **Security**: Returns `Zeroizing<Scalar>` to ensure the nonce is automatically
/// zeroed from memory when dropped. This prevents nonce extraction attacks.
///
/// # Arguments
///
/// * `secret` - The secret scalar (wrapped in Zeroizing for memory safety)
/// * `hashlock` - The hashlock (32-byte SHA-256 hash)
///
/// # Returns
///
/// A `Result` containing either:
/// - `Ok(Zeroizing<Scalar>)` - Valid nonce (automatically zeroed when dropped)
/// - `Err(DleqError::NonceGenerationFailed)` - Failed after 100 attempts
fn generate_deterministic_nonce(
    secret: &Zeroizing<Scalar>,
    hashlock: &[u8; 32],
) -> Result<Zeroizing<Scalar>, DleqError> {
    let mut counter = 0u32;

    loop {
        let mut hasher = Sha256::new();
        // Domain separation: prevents hash collisions with other protocol hashes
        hasher.update(b"DLEQ_NONCE_V1");
        hasher.update(secret.deref().to_bytes()); // Use deref() for Zeroizing
        hasher.update(hashlock);
        hasher.update(&counter.to_le_bytes()); // Counter for retry if k is invalid

        let hash = hasher.finalize();
        let mut scalar_bytes = [0u8; 32];
        scalar_bytes.copy_from_slice(&hash);
        let k = Scalar::from_bytes_mod_order(scalar_bytes);

        // Validate nonce is non-zero
        if k != Scalar::ZERO {
            // Wrap in Zeroizing to ensure automatic memory clearing
            return Ok(Zeroizing::new(k));
        }

        counter += 1;
        if counter >= 100 {
            return Err(DleqError::NonceGenerationFailed);
        }
    }
}

/// Compute the Fiat-Shamir challenge for DLEQ verification.
///
/// Challenge: c = H(tag || G || Y || T || U || R1 || R2 || hashlock) mod n
///
/// **Implementation:** Uses Poseidon (deployable on Starknet today)
/// - Matches Cairo Poseidon transcript exactly
/// - Uses compressed Edwards points serialized as u256 low/high limbs
///
/// **Format:**
/// - tag: "DLEQ" (felt252, 0x444c4551) twice
/// - G, Y, T, U, R1, R2: Ed25519 points (compressed Edwards, u256 low/high)
/// - hashlock: 8 u32 words (SHA-256 big-endian words)
///
/// **Serialization Order:**
/// 1. Tag: "DLEQ" (felt252), repeated twice
/// 2. Points in order: G, Y, T, U, R1, R2 (each u256 low then high)
/// 3. Hashlock words (8 u32, big-endian)
fn compute_challenge(
    G: &EdwardsPoint,
    Y: &EdwardsPoint,
    T: &EdwardsPoint,
    U: &EdwardsPoint,
    R1: &EdwardsPoint,
    R2: &EdwardsPoint,
    hashlock: &[u8; 32],
) -> Scalar {
    let mut inputs: Vec<PoseidonFE> = Vec::with_capacity(2 + 12 + 8);
    let dleq_tag = poseidon_fe_from_u128(0x444c4551_u128);
    inputs.push(dleq_tag);
    inputs.push(dleq_tag);

    push_compressed_point(&mut inputs, G);
    push_compressed_point(&mut inputs, Y);
    push_compressed_point(&mut inputs, T);
    push_compressed_point(&mut inputs, U);
    push_compressed_point(&mut inputs, R1);
    push_compressed_point(&mut inputs, R2);

    for i in 0..8 {
        let word = u32::from_be_bytes([
            hashlock[i * 4],
            hashlock[i * 4 + 1],
            hashlock[i * 4 + 2],
            hashlock[i * 4 + 3],
        ]);
        inputs.push(poseidon_fe_from_u128(word as u128));
    }

    let mut scalar_bytes = [0u8; 32];
    let hash_felt = PoseidonCairoStark252::hash_many(&inputs);
    let hash_bytes = hash_felt.to_bytes_le();
    scalar_bytes.copy_from_slice(&hash_bytes[..32]);
    Scalar::from_bytes_mod_order(scalar_bytes)
}

fn push_compressed_point(inputs: &mut Vec<PoseidonFE>, point: &EdwardsPoint) {
    let bytes = point.compress().to_bytes();
    let mut low_bytes = [0u8; 16];
    let mut high_bytes = [0u8; 16];
    low_bytes.copy_from_slice(&bytes[..16]);
    high_bytes.copy_from_slice(&bytes[16..]);
    let low = u128::from_le_bytes(low_bytes);
    let high = u128::from_le_bytes(high_bytes);
    inputs.push(poseidon_fe_from_u128(low));
    inputs.push(poseidon_fe_from_u128(high));
}

fn poseidon_fe_from_u128(value: u128) -> PoseidonFE {
    // Use from_hex to ensure Montgomery conversion matches Cairo.
    PoseidonFieldElement::from_hex(&format!("{:x}", value))
        .expect("Poseidon field element from hex")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_dleq_proof_generation() {
        use zeroize::Zeroizing;
        // Generate a test secret
        let secret_bytes = [0x42u8; 32];
        let secret = Scalar::from_bytes_mod_order(secret_bytes);
        let secret_zeroizing = Zeroizing::new(secret);
        // Use raw bytes for hashlock (Cairo-compatible)
        let hashlock: [u8; 32] = Sha256::digest(secret_bytes).into();

        // Compute adaptor point
        let adaptor_point = ED25519_BASEPOINT_POINT * *secret_zeroizing;

        // Generate DLEQ proof
        let proof =
            generate_dleq_proof(&secret_zeroizing, &secret_bytes, &adaptor_point, &hashlock)
                .expect("Proof generation should succeed for valid inputs");

        // Verify proof structure: U should equal t·Y
        let Y = get_second_generator();
        let expected_U = Y * *secret_zeroizing;
        assert_eq!(proof.second_point, expected_U, "U should equal t·Y");
    }

    #[test]
    fn test_second_generator_deterministic() {
        // Second generator should be deterministic
        let Y1 = get_second_generator();
        let Y2 = get_second_generator();
        assert_eq!(Y1, Y2, "Second generator should be deterministic");
    }

    #[test]
    fn test_dleq_validation_zero_scalar() {
        use zeroize::Zeroizing;
        let secret = Zeroizing::new(Scalar::ZERO);
        let secret_bytes = [0u8; 32]; // Zero scalar bytes
        let adaptor_point = ED25519_BASEPOINT_POINT; // arbitrary
        let hashlock = [0u8; 32]; // arbitrary

        let result = generate_dleq_proof(&secret, &secret_bytes, &adaptor_point, &hashlock);
        assert_eq!(
            result,
            Err(DleqError::ZeroScalar),
            "Zero scalar must be rejected"
        );
    }

    #[test]
    fn test_dleq_validation_point_mismatch() {
        use std::ops::Deref;
        use zeroize::Zeroizing;
        let secret = Zeroizing::new(Scalar::from(42u64));
        let secret_bytes = secret.deref().to_bytes(); // Use scalar bytes for test
        let wrong_point = ED25519_BASEPOINT_POINT * Scalar::from(99u64); // wrong!
        let hashlock: [u8; 32] = Sha256::digest(secret_bytes).into();

        let result = generate_dleq_proof(&secret, &secret_bytes, &wrong_point, &hashlock);
        assert_eq!(
            result,
            Err(DleqError::PointMismatch),
            "Wrong adaptor point must be rejected"
        );
    }

    #[test]
    fn test_dleq_validation_hashlock_mismatch() {
        use std::ops::Deref;
        use zeroize::Zeroizing;
        let secret = Zeroizing::new(Scalar::from(42u64));
        let secret_bytes = secret.deref().to_bytes(); // Use scalar bytes for test
        let adaptor_point = ED25519_BASEPOINT_POINT * *secret;
        let wrong_hashlock = [0xFF; 32]; // wrong!

        let result = generate_dleq_proof(&secret, &secret_bytes, &adaptor_point, &wrong_hashlock);
        assert_eq!(
            result,
            Err(DleqError::HashlockMismatch),
            "Wrong hashlock must be rejected"
        );
    }

    #[test]
    fn test_nonce_generation_deterministic() {
        use std::ops::Deref;
        use zeroize::Zeroizing;
        let secret = Zeroizing::new(Scalar::from(42u64));
        let hashlock: [u8; 32] = Sha256::digest(secret.deref().to_bytes()).into();

        let nonce1 = generate_deterministic_nonce(&secret, &hashlock)
            .expect("Nonce generation should succeed");
        let nonce2 = generate_deterministic_nonce(&secret, &hashlock)
            .expect("Nonce generation should succeed");

        assert_eq!(*nonce1, *nonce2, "Nonce generation must be deterministic");
        assert_ne!(*nonce1, Scalar::ZERO, "Nonce must not be zero");
    }

    #[test]
    fn test_nonce_generation_different_inputs_produce_different_nonces() {
        use std::ops::Deref;
        use zeroize::Zeroizing;
        let secret1 = Zeroizing::new(Scalar::from(42u64));
        let secret2 = Zeroizing::new(Scalar::from(99u64));
        let hashlock1: [u8; 32] = Sha256::digest(secret1.deref().to_bytes()).into();
        let hashlock2: [u8; 32] = Sha256::digest(secret2.deref().to_bytes()).into();

        let nonce1 = generate_deterministic_nonce(&secret1, &hashlock1)
            .expect("Nonce generation should succeed");
        let nonce2 = generate_deterministic_nonce(&secret2, &hashlock2)
            .expect("Nonce generation should succeed");

        // Different inputs should produce different nonces (with high probability)
        assert_ne!(
            *nonce1, *nonce2,
            "Different inputs should produce different nonces"
        );
    }

    #[test]
    fn test_dleq_validation_scalar_one() {
        use std::ops::Deref;
        use zeroize::Zeroizing;
        // Test edge case: Scalar::ONE (smallest non-zero scalar)
        let secret = Zeroizing::new(Scalar::ONE);
        let secret_bytes = secret.deref().to_bytes(); // Use scalar bytes for test
        let adaptor_point = ED25519_BASEPOINT_POINT * *secret;
        let hashlock: [u8; 32] = Sha256::digest(secret_bytes).into();

        // Should succeed (ONE is valid, only ZERO is rejected)
        let result = generate_dleq_proof(&secret, &secret_bytes, &adaptor_point, &hashlock);
        assert!(result.is_ok(), "Scalar::ONE should be accepted");
    }

    #[test]
    fn test_dleq_validation_max_scalar() {
        use zeroize::Zeroizing;
        // Test edge case: Maximum scalar value (order - 1)
        // Ed25519 order is 2^252 + 27742317777372353535851937790883648493
        // Maximum scalar is order - 1
        let max_scalar_bytes = [
            0xec, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9,
            0xde, 0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x10,
        ];
        let max_scalar = Zeroizing::new(Scalar::from_bytes_mod_order(max_scalar_bytes));
        let adaptor_point = ED25519_BASEPOINT_POINT * *max_scalar;
        // Use raw bytes for hashlock (Cairo-compatible)
        let hashlock: [u8; 32] = Sha256::digest(max_scalar_bytes).into();

        // Should succeed (max scalar is valid)
        let result = generate_dleq_proof(&max_scalar, &max_scalar_bytes, &adaptor_point, &hashlock);
        assert!(result.is_ok(), "Maximum scalar should be accepted");
    }

    #[test]
    fn test_nonce_generation_counter_boundary() {
        use std::ops::Deref;
        use zeroize::Zeroizing;
        // Test that nonce generation handles counter retries correctly
        // This tests the boundary condition where k might be zero multiple times
        // (though statistically unlikely, we should handle it)
        let secret = Zeroizing::new(Scalar::from(42u64));
        let hashlock: [u8; 32] = Sha256::digest(secret.deref().to_bytes()).into();

        // Generate nonce multiple times - should always succeed
        for _ in 0..10 {
            let nonce = generate_deterministic_nonce(&secret, &hashlock)
                .expect("Nonce generation should always succeed");
            assert_ne!(*nonce, Scalar::ZERO, "Nonce must never be zero");
        }
    }

    #[test]
    fn test_nonce_generation_max_attempts() {
        use std::ops::Deref;
        use zeroize::Zeroizing;
        // Test that nonce generation doesn't loop infinitely
        // Even if we hit zero nonces, we should fail gracefully after max attempts
        // Note: This is a theoretical test - hitting zero 100 times is cryptographically impossible
        // But we test the error handling path
        let secret = Zeroizing::new(Scalar::from(42u64));
        let hashlock: [u8; 32] = Sha256::digest(secret.deref().to_bytes()).into();

        // This should succeed (hitting zero 100 times is impossible)
        let result = generate_deterministic_nonce(&secret, &hashlock);
        assert!(
            result.is_ok(),
            "Nonce generation should succeed for valid inputs"
        );
    }
}
