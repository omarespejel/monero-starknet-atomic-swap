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

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::edwards::EdwardsPoint;
use curve25519_dalek::scalar::Scalar;
use sha2::{Digest, Sha256};

/// DLEQ proof structure containing the second point, challenge, and response.
pub struct DleqProof {
    /// Second point U = t·Y
    pub second_point: EdwardsPoint,
    /// Challenge scalar c
    pub challenge: Scalar,
    /// Response scalar s = k + c·t mod n
    pub response: Scalar,
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
    }
}

/// Get the second generator point Y for DLEQ proofs.
///
/// This uses a deterministic approach to derive Y.
/// The point Y must be fixed and known to both prover and verifier.
///
/// Currently uses Y = 2·G as a simple deterministic second generator.
/// This matches the Cairo implementation placeholder.
/// TODO: Replace with proper hash-to-curve("DLEQ_SECOND_BASE") for production.
fn get_second_generator() -> EdwardsPoint {
    // Use 2·G as second generator (matches Cairo placeholder)
    // In production, this should be replaced with hash-to-curve("DLEQ_SECOND_BASE")
    let two = Scalar::from(2u64);
    ED25519_BASEPOINT_POINT * two
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
/// Where:
/// - tag: "DLEQ" (double SHA-256 for domain separation)
/// - G, Y, T, U, R1, R2: Ed25519 points (compressed format)
/// - hashlock: 32-byte hash
fn compute_challenge(
    G: &EdwardsPoint,
    Y: &EdwardsPoint,
    T: &EdwardsPoint,
    U: &EdwardsPoint,
    R1: &EdwardsPoint,
    R2: &EdwardsPoint,
    hashlock: &[u8; 32],
) -> Scalar {
    let mut hasher = Sha256::new();

    // Tag: SHA256("DLEQ") || SHA256("DLEQ") for domain separation
    let tag = Sha256::digest(b"DLEQ");
    hasher.update(tag);
    hasher.update(tag);

    // Serialize points in compressed format (32 bytes each)
    hasher.update(G.compress().as_bytes());
    hasher.update(Y.compress().as_bytes());
    hasher.update(T.compress().as_bytes());
    hasher.update(U.compress().as_bytes());
    hasher.update(R1.compress().as_bytes());
    hasher.update(R2.compress().as_bytes());
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

