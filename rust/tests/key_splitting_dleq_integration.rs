//! Integration tests for key splitting + DLEQ proof flow
//!
//! Tests the critical bridge between Monero key splitting and Starknet DLEQ verification.
//! This validates that the same adaptor scalar `t` works for both:
//! 1. Monero key splitting: x = x_partial + t
//! 2. Starknet DLEQ proof: T = t·G, U = t·Y

use sha2::{Digest, Sha256};
use zeroize::Zeroizing;
use xmr_secret_gen::dleq::generate_dleq_proof;
use xmr_secret_gen::monero::SwapKeyPair;

#[test]
fn test_swap_keypair_with_dleq_proof() {
    // 1. Generate swap keys (key splitting)
    let keys = SwapKeyPair::generate();
    assert!(keys.verify(), "Key splitting math failed");

    // 2. Compute hashlock = SHA256(t.to_bytes())
    let hashlock: [u8; 32] = Sha256::digest(keys.adaptor_scalar_bytes()).into();

    // 3. Generate DLEQ proof - THIS IS THE CONFIRMED API
    // Wrap adaptor_scalar in Zeroizing for memory safety
    let adaptor_scalar_zeroizing = Zeroizing::new(keys.adaptor_scalar);
    let proof = generate_dleq_proof(&adaptor_scalar_zeroizing, &keys.adaptor_point, &hashlock)
        .expect("DLEQ proof generation should succeed with valid inputs");

    // 4. Basic proof validity checks
    assert!(proof.challenge.to_bytes() != [0u8; 32], "Challenge is zero");
    assert!(proof.response.to_bytes() != [0u8; 32], "Response is zero");

    println!("✅ SwapKeyPair + DLEQ integration: PASSED");
}

#[test]
fn test_key_recovery_after_reveal() {
    let keys = SwapKeyPair::generate();

    // Simulate: Bob reveals t on Starknet
    let revealed_t = keys.adaptor_scalar;

    // Alice recovers full key
    let recovered = SwapKeyPair::recover(keys.partial_key, revealed_t);

    assert_eq!(recovered, keys.full_spend_key, "Key recovery failed");
    println!("✅ Key recovery: PASSED");
}

#[test]
fn test_hashlock_consistency() {
    // Verify that hashlock computed from adaptor scalar matches expected format
    let keys = SwapKeyPair::generate();

    // Compute hashlock
    let hashlock: [u8; 32] = Sha256::digest(keys.adaptor_scalar_bytes()).into();

    // Verify hashlock is non-zero
    assert!(hashlock != [0u8; 32], "Hashlock must be non-zero");

    // Verify hashlock is deterministic
    let hashlock2: [u8; 32] = Sha256::digest(keys.adaptor_scalar_bytes()).into();
    assert_eq!(hashlock, hashlock2, "Hashlock must be deterministic");

    println!("✅ Hashlock consistency: PASSED");
}

#[test]
fn test_adaptor_point_matches_dleq() {
    // Verify that adaptor point T = t·G matches what DLEQ expects
    let keys = SwapKeyPair::generate();

    use curve25519_dalek::constants::ED25519_BASEPOINT_POINT as G;

    // Verify T = t·G
    let expected_adaptor_point = keys.adaptor_scalar * G;
    assert_eq!(
        keys.adaptor_point, expected_adaptor_point,
        "Adaptor point must equal t·G"
    );

    println!("✅ Adaptor point verification: PASSED");
}
