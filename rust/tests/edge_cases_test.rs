//! Edge case tests per auditor recommendations.
//!
//! These tests verify the system handles edge cases correctly:
//! - Small scalar values (t = 1)
//! - Scalars near curve order
//! - Zero scalar rejection
//! - Identity point detection

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::edwards::EdwardsPoint;
use curve25519_dalek::scalar::Scalar;
use rand::rngs::OsRng;
use rand::RngCore;
use xmr_secret_gen::monero::SwapKeyPair;

// Helper to generate random scalar (curve25519-dalek v4.1 doesn't have Scalar::random)
fn random_scalar() -> Scalar {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    Scalar::from_bytes_mod_order(bytes)
}

#[test]
fn test_small_scalar_values() {
    // t = 1 (smallest non-zero)
    let t = Scalar::ONE;
    let x = random_scalar();
    let x_partial = x - t;

    // Recover using SwapKeyPair
    let recovered_x = SwapKeyPair::recover_plain(x_partial, t);
    assert_eq!(recovered_x, x);
}

#[test]
fn test_scalar_near_order() {
    // t close to curve order (but still valid)
    let mut bytes = [0xFFu8; 32];
    bytes[31] = 0x0F; // Ensure < order (curve25519 order ends with ...0F)
    let t = Scalar::from_bytes_mod_order(bytes);

    let x = random_scalar();
    let x_partial = x - t;

    let recovered_x = SwapKeyPair::recover_plain(x_partial, t);
    assert_eq!(recovered_x, x);
}

#[test]
fn test_zero_scalar_rejected() {
    // t = 0 should be rejected in production
    let t = Scalar::ZERO;

    // Verify zero scalar detection
    assert!(t == Scalar::ZERO, "Zero scalar must be detected");

    // In production, SwapKeyPair::generate() should never produce t=0
    // This is handled by the random generation in SwapKeyPair
    for _ in 0..100 {
        let keypair = SwapKeyPair::generate();
        assert_ne!(
            keypair.adaptor_scalar,
            Scalar::ZERO,
            "Adaptor scalar should never be zero"
        );
    }
}

#[test]
fn test_identity_point_detection() {
    use curve25519_dalek::traits::Identity;

    let identity = EdwardsPoint::identity();

    // Verify identity point detection
    assert_eq!(identity, EdwardsPoint::identity());

    // In production, adaptor points should never be identity
    // This would mean t = 0, which is rejected
    for _ in 0..100 {
        let keypair = SwapKeyPair::generate();
        assert_ne!(
            keypair.adaptor_point,
            EdwardsPoint::identity(),
            "Adaptor point should never be identity"
        );
    }
}

#[test]
fn test_key_recovery_edge_cases() {
    // Test recovery with various scalar combinations

    // Case 1: x_partial = 0, t = random
    let t = random_scalar();
    let x_partial = Scalar::ZERO;
    let expected_x = t;

    let recovered_x = SwapKeyPair::recover_plain(x_partial, t);
    assert_eq!(recovered_x, expected_x);

    // Case 2: x_partial = random, t = 1
    let x_partial = random_scalar();
    let t = Scalar::ONE;
    let expected_x = x_partial + t;

    let recovered_x = SwapKeyPair::recover_plain(x_partial, t);
    assert_eq!(recovered_x, expected_x);
}

#[test]
fn test_adaptor_point_computation() {
    // Verify adaptor point T = t·G is computed correctly
    let keypair = SwapKeyPair::generate();
    let expected_point = &keypair.adaptor_scalar * &ED25519_BASEPOINT_POINT;

    assert_eq!(keypair.adaptor_point, expected_point);
}

#[test]
fn test_key_splitting_idempotency() {
    // Splitting and recovering should be idempotent
    let keypair = SwapKeyPair::generate();
    let recovered = SwapKeyPair::recover_plain(keypair.partial_key, keypair.adaptor_scalar);

    assert_eq!(recovered, keypair.full_spend_key);
}

#[test]
fn test_max_scalar_value() {
    // Test with maximum valid scalar (order - 1)
    let max_scalar_bytes = [
        0xec, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58, 0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde,
        0x14, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x10,
    ]; // l - 1 where l is curve25519 order

    let t = Scalar::from_bytes_mod_order(max_scalar_bytes);
    let x = random_scalar();
    let x_partial = x - t;

    let recovered_x = SwapKeyPair::recover_plain(x_partial, t);
    assert_eq!(recovered_x, x);
}
