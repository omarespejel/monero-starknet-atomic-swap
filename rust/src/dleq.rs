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
use curve25519_dalek::edwards::EdwardsPoint;
use curve25519_dalek::scalar::Scalar;
use sha2::{Digest, Sha256};

// TODO: Uncomment when Poseidon is fully implemented
// mod poseidon;
// use poseidon::compute_poseidon_challenge;

/// DLEQ proof structure containing the second point, challenge, response, and commitments.
pub struct DleqProof {
    /// Second point U = t·Y
    pub second_point: EdwardsPoint,
    /// Challenge scalar c
    pub challenge: Scalar,
    /// Response scalar s = k + c·t mod n
    pub response: Scalar,
    /// First commitment R1 = k·G (needed for Cairo challenge computation)
    pub r1: EdwardsPoint,
    /// Second commitment R2 = k·Y (needed for Cairo challenge computation)
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
/// # Arguments
///
/// * `secret` - The secret scalar t
/// * `adaptor_point` - The adaptor point T = t·G
/// * `hashlock` - The hashlock (32-byte SHA-256 hash of the secret)
///
/// # Returns
///
/// A `DleqProof` containing U, c, and s.
pub fn generate_dleq_proof(
    secret: &Scalar,
    adaptor_point: &EdwardsPoint,
    hashlock: &[u8; 32],
) -> DleqProof {
    // 1. Get generators
    let G = ED25519_BASEPOINT_POINT; // Standard Ed25519 generator
    let Y = get_second_generator(); // Derived second base

    // 2. Compute U = t·Y
    let U = Y * secret;

    // 3. Generate nonce k (deterministic for reproducibility in tests)
    // Using RFC6979-style deterministic nonce generation
    let k = generate_deterministic_nonce(secret, hashlock);

    // 4. Compute commitments
    let R1 = G * k; // k·G
    let R2 = Y * k; // k·Y

    // 5. Compute Fiat-Shamir challenge
    let c = compute_challenge(&G, &Y, adaptor_point, &U, &R1, &R2, hashlock);

    // 6. Compute response s = k + c·t mod n
    let s = k + (c * secret);

    DleqProof {
        second_point: U,
        challenge: c,
        response: s,
        r1: R1,
        r2: R2,
    }
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

impl DleqProof {
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
fn get_second_generator() -> EdwardsPoint {
    // Current implementation: Y = 2·G (matches Cairo placeholder)
    // This ensures compatibility between Rust proof generation and Cairo verification
    ED25519_BASEPOINT_POINT * Scalar::from(2u64)
}

/// Generate a deterministic nonce k for DLEQ proof generation.
///
/// Uses RFC6979-style deterministic nonce generation based on the secret and hashlock.
/// This ensures reproducibility in tests while maintaining security.
fn generate_deterministic_nonce(secret: &Scalar, hashlock: &[u8; 32]) -> Scalar {
    // RFC6979-style: k = SHA256(secret || hashlock || counter)
    // For simplicity, use single hash (can be extended with counter if needed)
    let mut hasher = Sha256::new();
    hasher.update(secret.to_bytes());
    hasher.update(hashlock);
    hasher.update(&[0u8; 1]); // Counter (can be incremented if k is invalid)

    let hash = hasher.finalize();
    let mut scalar_bytes = [0u8; 32];
    scalar_bytes.copy_from_slice(&hash);
    Scalar::from_bytes_mod_order(scalar_bytes)
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

    #[test]
    fn test_dleq_proof_generation() {
        // Generate a test secret
        let secret_bytes = [0x42u8; 32];
        let secret = Scalar::from_bytes_mod_order(secret_bytes);
        let hashlock: [u8; 32] = Sha256::digest(&secret_bytes).into();

        // Compute adaptor point
        let adaptor_point = ED25519_BASEPOINT_POINT * secret;

        // Generate DLEQ proof
        let proof = generate_dleq_proof(&secret, &adaptor_point, &hashlock);

        // Verify proof structure: U should equal t·Y
        let Y = get_second_generator();
        let expected_U = Y * secret;
        assert_eq!(proof.second_point, expected_U, "U should equal t·Y");
    }

    #[test]
    fn test_second_generator_deterministic() {
        // Second generator should be deterministic
        let Y1 = get_second_generator();
        let Y2 = get_second_generator();
        assert_eq!(Y1, Y2, "Second generator should be deterministic");
    }
}
