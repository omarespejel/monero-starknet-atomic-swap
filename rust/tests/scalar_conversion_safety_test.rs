//! TDD Tests for Ed25519 → BN254 Scalar Conversion Safety
//!
//! CRITICAL: This prevents cross-curve security vulnerabilities
//! Reference: https://github.com/Lightprotocol/light-protocol/issues/237

use curve25519_dalek::scalar::Scalar as Ed25519Scalar;

// This import will fail until we implement
use xmr_secret_gen::dleq::ed25519_bn254::{
    ed25519_scalar_to_bn254_safe, Ed25519Bn254ConversionError, BN254_PRIME, ED25519_ORDER,
};

/// Security invariant: Ed25519 order < BN254 prime
#[test]
fn test_security_invariant_order_less_than_prime() {
    use num_bigint::BigUint;

    // Ed25519 order: l = 2^252 + 27742317777372353535851937790883648493
    // BN254 prime: p ≈ 2^254
    let ed25519_order = BigUint::from_bytes_le(&ED25519_ORDER);
    let bn254_prime = BigUint::from_bytes_le(&BN254_PRIME);

    assert!(
        ed25519_order < bn254_prime,
        "SECURITY VIOLATION: Ed25519 order must be less than BN254 prime"
    );
}

/// Valid Ed25519 scalars convert successfully
#[test]
fn test_valid_scalar_converts() {
    // Small scalar (definitely valid)
    let small_bytes = [0x42u8; 32];
    let scalar = Ed25519Scalar::from_bytes_mod_order(small_bytes);

    let result = ed25519_scalar_to_bn254_safe(&scalar);
    assert!(result.is_ok(), "Valid scalar must convert successfully");
}

/// Conversion preserves scalar value for small inputs
#[test]
fn test_conversion_preserves_small_values() {
    let mut bytes = [0u8; 32];
    bytes[0] = 42; // Small value

    let scalar = Ed25519Scalar::from_bytes_mod_order(bytes);
    let converted = ed25519_scalar_to_bn254_safe(&scalar).expect("Small scalar must convert");

    // Value should be identical
    assert_eq!(converted[0], 42);
    assert!(converted[1..].iter().all(|&b| b == 0));
}

/// Conversion is deterministic
#[test]
fn test_conversion_deterministic() {
    let bytes = [0x12u8; 32];
    let scalar = Ed25519Scalar::from_bytes_mod_order(bytes);

    let result1 = ed25519_scalar_to_bn254_safe(&scalar).unwrap();
    let result2 = ed25519_scalar_to_bn254_safe(&scalar).unwrap();

    assert_eq!(result1, result2, "Conversion must be deterministic");
}

/// Canonical test vector matches expected output
#[test]
fn test_canonical_vector_conversion() {
    // Canonical secret: 0x12 repeated 32 times
    let secret_bytes = [0x12u8; 32];
    let scalar = Ed25519Scalar::from_bytes_mod_order(secret_bytes);

    let converted = ed25519_scalar_to_bn254_safe(&scalar).expect("Canonical vector must convert");

    // The converted value should equal the scalar bytes
    // (since this value is well within both field orders)
    assert_eq!(converted, scalar.to_bytes());
}

/// Edge case: Maximum valid Ed25519 scalar
#[test]
fn test_max_valid_ed25519_scalar() {
    // Create scalar just under Ed25519 order
    // l - 1 is the maximum valid scalar
    let mut max_bytes = [0xFFu8; 32];
    // Ed25519 scalars are reduced mod l automatically
    let scalar = Ed25519Scalar::from_bytes_mod_order(max_bytes);

    // Should still convert (l < p)
    let result = ed25519_scalar_to_bn254_safe(&scalar);
    assert!(result.is_ok(), "Max valid Ed25519 scalar must convert");
}

/// Zero scalar converts to zero
#[test]
fn test_zero_scalar_converts() {
    let zero = Ed25519Scalar::ZERO;
    let converted = ed25519_scalar_to_bn254_safe(&zero).expect("Zero scalar must convert");

    assert_eq!(converted, [0u8; 32]);
}

/// One scalar converts to one
#[test]
fn test_one_scalar_converts() {
    let one = Ed25519Scalar::ONE;
    let converted = ed25519_scalar_to_bn254_safe(&one).expect("One scalar must convert");

    let mut expected = [0u8; 32];
    expected[0] = 1;
    assert_eq!(converted, expected);
}
