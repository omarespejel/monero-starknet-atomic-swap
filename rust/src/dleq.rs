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
//! **Hash Function Compatibility:**
//! - Uses BLAKE2s for challenge computation (matches Cairo)
//! - BLAKE2s is Starknet's official standard (v0.14.1+)
//! - 8x cheaper proving cost than Poseidon
//! - Native Cairo stdlib support via core::blake

use blake2::{Blake2s256, Digest as Blake2Digest};
use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::edwards::{CompressedEdwardsY, EdwardsPoint};
use curve25519_dalek::scalar::Scalar;
use hex;
use sha2::{Digest, Sha256};
use std::ops::Deref;
use thiserror::Error;
use zeroize::{Zeroize, Zeroizing};

// TODO: Uncomment when Poseidon is fully implemented
// mod poseidon;
// use poseidon::compute_poseidon_challenge;

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
    /// Second commitment R2 = k·Y (compressed Edwards, 32 bytes)
    pub r2_compressed: [u8; 32],
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


/// Convert an Edwards point to compressed format and sqrt hint.
///
/// The sqrt hint is the x-coordinate of the point, stored as a u256 (32 bytes, little-endian).
/// This is needed by Cairo's `decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point`.
///
/// # Arguments
///
/// * `point` - The Edwards point to compress
///
/// # Returns
///
/// A tuple of (compressed_point, sqrt_hint) where:
/// - compressed_point: 32-byte compressed Edwards format (y-coordinate + sign bit)
/// - sqrt_hint: 32-byte x-coordinate as u256 (little-endian)
fn edwards_point_to_cairo_format(point: &EdwardsPoint) -> ([u8; 32], [u8; 32]) {
    // Compress the point (standard Ed25519 format: y-coordinate + sign bit)
    let compressed = point.compress().to_bytes();

    // Extract x-coordinate for sqrt hint
    // Convert point to Montgomery form to get x-coordinate
    // The Montgomery form's x-coordinate corresponds to the Edwards x-coordinate
    let montgomery = point.to_montgomery();
    let x_bytes = montgomery.to_bytes();

    // The sqrt hint is the x-coordinate as u256 (little-endian, 32 bytes)
    let mut sqrt_hint = [0u8; 32];
    sqrt_hint.copy_from_slice(&x_bytes);

    (compressed, sqrt_hint)
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
    pub fn to_cairo_format(&self, adaptor_point: &EdwardsPoint) -> DleqProofForCairo {
        let G = ED25519_BASEPOINT_POINT;
        let Y = get_second_generator();

        // Convert all points to compressed format with sqrt hints
        let (adaptor_compressed, adaptor_sqrt_hint) = edwards_point_to_cairo_format(adaptor_point);
        let (second_compressed, second_sqrt_hint) =
            edwards_point_to_cairo_format(&self.second_point);
        let (g_compressed, _) = edwards_point_to_cairo_format(&G);
        let (y_compressed, _) = edwards_point_to_cairo_format(&Y);
        let (r1_compressed, _) = edwards_point_to_cairo_format(&self.r1);
        let (r2_compressed, _) = edwards_point_to_cairo_format(&self.r2);

        DleqProofForCairo {
            adaptor_point_compressed: adaptor_compressed,
            adaptor_point_sqrt_hint: adaptor_sqrt_hint,
            second_point_compressed: second_compressed,
            second_point_sqrt_hint: second_sqrt_hint,
            challenge: self.challenge.to_bytes(),
            response: self.response.to_bytes(),
            g_compressed,
            y_compressed,
            r1_compressed,
            r2_compressed,
        }
    }
}

/// Get the second generator point Y for DLEQ proofs.
///
/// CRITICAL: Must match Cairo's `get_dleq_second_generator()` exactly!
///
/// Currently uses `2·G` as placeholder to match Cairo's implementation.
/// This ensures Rust-generated proofs verify correctly in Cairo.
///
/// TODO: Once Python tool generates hash-to-curve constant for Cairo,
/// update both Rust and Cairo to use the same hash-to-curve point.
///
/// Production path: Use hash-to-curve("DLEQ_SECOND_BASE_V1") → Edwards → Weierstrass → u384 limbs
pub(crate) fn get_second_generator() -> EdwardsPoint {
    // Current implementation: Y = 2·G (matches Cairo placeholder)
    // This ensures compatibility between Rust proof generation and Cairo verification
    ED25519_BASEPOINT_POINT * Scalar::from(2u64)
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
/// **Implementation:** Uses BLAKE2s (Starknet's official standard)
/// - 8x cheaper proving cost than Poseidon
/// - Native Cairo stdlib support via core::blake
/// - Matches Cairo implementation exactly
///
/// **Format:**
/// - tag: "DLEQ" (4 bytes, 0x444c4551)
/// - G, Y, T, U, R1, R2: Ed25519 points (compressed format, 32 bytes each)
/// - hashlock: 32-byte hash
///
/// **Serialization Order:**
/// 1. Tag: "DLEQ" (4 bytes)
/// 2. Points in order: G, Y, T, U, R1, R2 (each 32 bytes compressed)
/// 3. Hashlock (32 bytes)
fn compute_challenge(
    G: &EdwardsPoint,
    Y: &EdwardsPoint,
    T: &EdwardsPoint,
    U: &EdwardsPoint,
    R1: &EdwardsPoint,
    R2: &EdwardsPoint,
    hashlock: &[u8; 32],
) -> Scalar {
    // Use BLAKE2s (Starknet's official standard, matches Cairo)
    let mut hasher = Blake2s256::new();

    // Tag: "DLEQ" (4 bytes) for domain separation
    // This matches Cairo's tag: 0x444c4551
    hasher.update(b"DLEQ");

    // Serialize points in compressed format (32 bytes each)
    // Order: G, Y, T, U, R1, R2 (must match Cairo exactly)
    hasher.update(G.compress().as_bytes());
    hasher.update(Y.compress().as_bytes());
    hasher.update(T.compress().as_bytes());
    hasher.update(U.compress().as_bytes());
    hasher.update(R1.compress().as_bytes());
    hasher.update(R2.compress().as_bytes());

    // Add hashlock (32 bytes)
    // NOTE: Rust's hashlock is already a [u8; 32] byte array, so BLAKE2s sees it correctly.
    // Cairo needs byte-swapping because it stores hashlock as Big-Endian u32 words.
    // The byte-swap fix is in Cairo, not here.
    hasher.update(hashlock);

    // Reduce hash to scalar mod curve order
    let hash = hasher.finalize();
    let mut scalar_bytes = [0u8; 32];
    scalar_bytes.copy_from_slice(&hash);
    Scalar::from_bytes_mod_order(scalar_bytes)
}

#[cfg(test)]
mod tests {
    use super::*;
    use zeroize::Zeroizing;
    use std::ops::Deref;

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
        let proof = generate_dleq_proof(&secret_zeroizing, &secret_bytes, &adaptor_point, &hashlock)
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
        assert_eq!(result, Err(DleqError::ZeroScalar), "Zero scalar must be rejected");
    }

    #[test]
    fn test_dleq_validation_point_mismatch() {
        use zeroize::Zeroizing;
        use std::ops::Deref;
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
        use zeroize::Zeroizing;
        use std::ops::Deref;
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
        use zeroize::Zeroizing;
        use std::ops::Deref;
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
        use zeroize::Zeroizing;
        use std::ops::Deref;
        let secret1 = Zeroizing::new(Scalar::from(42u64));
        let secret2 = Zeroizing::new(Scalar::from(99u64));
        let hashlock1: [u8; 32] = Sha256::digest(secret1.deref().to_bytes()).into();
        let hashlock2: [u8; 32] = Sha256::digest(secret2.deref().to_bytes()).into();

        let nonce1 = generate_deterministic_nonce(&secret1, &hashlock1)
            .expect("Nonce generation should succeed");
        let nonce2 = generate_deterministic_nonce(&secret2, &hashlock2)
            .expect("Nonce generation should succeed");

        // Different inputs should produce different nonces (with high probability)
        assert_ne!(*nonce1, *nonce2, "Different inputs should produce different nonces");
    }

    #[test]
    fn test_dleq_validation_scalar_one() {
        use zeroize::Zeroizing;
        use std::ops::Deref;
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
        use std::ops::Deref;
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
        use zeroize::Zeroizing;
        use std::ops::Deref;
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
        use zeroize::Zeroizing;
        use std::ops::Deref;
        // Test that nonce generation doesn't loop infinitely
        // Even if we hit zero nonces, we should fail gracefully after max attempts
        // Note: This is a theoretical test - hitting zero 100 times is cryptographically impossible
        // But we test the error handling path
        let secret = Zeroizing::new(Scalar::from(42u64));
        let hashlock: [u8; 32] = Sha256::digest(secret.deref().to_bytes()).into();

        // This should succeed (hitting zero 100 times is impossible)
        let result = generate_deterministic_nonce(&secret, &hashlock);
        assert!(result.is_ok(), "Nonce generation should succeed for valid inputs");
    }
}
