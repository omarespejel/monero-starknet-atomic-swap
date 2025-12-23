//! TDD Tests for Ed25519 → BN254 Scalar Compatibility
//! 
//! SECURITY REQUIREMENT: Verify scalars are safe for cross-curve operations.
//! Reference: https://github.com/Lightprotocol/light-protocol/issues/237

use curve25519_dalek::scalar::Scalar;
use rand::rngs::OsRng;
use rand::RngCore;

// This import will fail until we implement the module
use xmr_secret_gen::crypto::scalar_compat::{
    verify_scalar_bn254_compatible,
    ed25519_scalar_to_bn254_bytes,
    ED25519_ORDER,
    BN254_FIELD_PRIME,
};

// ============================================================
// SECURITY TESTS - Ed25519 → BN254 Compatibility
// ============================================================

/// Ed25519 order must be less than BN254 field prime
#[test]
fn test_ed25519_order_less_than_bn254_prime() {
    use num_bigint::BigUint;
    
    // Ed25519 order: l = 2^252 + 27742317777372353535851937790883648493
    // BN254 prime:   p ≈ 2^254
    // 
    // This MUST hold for safe conversion
    let ed25519_order = BigUint::from_bytes_le(&ED25519_ORDER);
    let bn254_prime = BigUint::from_bytes_le(&BN254_FIELD_PRIME);
    
    assert!(
        ed25519_order < bn254_prime,
        "CRITICAL: Ed25519 order must be < BN254 prime for safe conversion"
    );
}

/// Any valid Ed25519 scalar is compatible with BN254
#[test]
fn test_valid_ed25519_scalar_is_compatible() {
    // Generate random scalar (will be < Ed25519 order by definition)
    let mut rng = OsRng;
    let mut raw_bytes = [0u8; 32];
    rng.fill_bytes(&mut raw_bytes);
    let scalar = Scalar::from_bytes_mod_order(raw_bytes);
    
    assert!(
        verify_scalar_bn254_compatible(&scalar),
        "Valid Ed25519 scalar must be BN254 compatible"
    );
}

/// Zero scalar is compatible
#[test]
fn test_zero_scalar_compatible() {
    let zero = Scalar::ZERO;
    
    assert!(
        verify_scalar_bn254_compatible(&zero),
        "Zero scalar must be compatible"
    );
}

/// Small scalars remain unchanged after conversion
#[test]
fn test_small_scalar_unchanged() {
    let small_value = 42u64;
    let scalar = Scalar::from(small_value);
    
    let bn254_bytes = ed25519_scalar_to_bn254_bytes(&scalar);
    let restored = u64::from_le_bytes(bn254_bytes[0..8].try_into().unwrap());
    
    assert_eq!(
        restored, small_value,
        "Small scalars must be unchanged after conversion"
    );
}

/// Large Ed25519 scalar (near order) is still compatible
#[test]
fn test_large_scalar_compatible() {
    // Create scalar near Ed25519 order (but still valid)
    let large_bytes = [0xFF; 32];
    let scalar = Scalar::from_bytes_mod_order(large_bytes);
    
    // After mod_order, this is a valid Ed25519 scalar
    assert!(
        verify_scalar_bn254_compatible(&scalar),
        "Large (reduced) scalar must be compatible"
    );
}

/// Conversion is deterministic
#[test]
fn test_conversion_deterministic() {
    let scalar = Scalar::from(12345u64);
    
    let bytes1 = ed25519_scalar_to_bn254_bytes(&scalar);
    let bytes2 = ed25519_scalar_to_bn254_bytes(&scalar);
    
    assert_eq!(bytes1, bytes2, "Conversion must be deterministic");
}

/// Conversion preserves scalar value (no modular reduction needed)
#[test]
fn test_conversion_preserves_value() {
    use num_bigint::BigUint;
    
    let scalar = Scalar::from(999999u64);
    let original_bytes = scalar.to_bytes();
    let converted_bytes = ed25519_scalar_to_bn254_bytes(&scalar);
    
    let original_int = BigUint::from_bytes_le(&original_bytes);
    let converted_int = BigUint::from_bytes_le(&converted_bytes);
    
    assert_eq!(
        original_int, converted_int,
        "Ed25519 scalars should not need reduction for BN254"
    );
}

// ============================================================
// PROPERTY TESTS - Fuzz the conversion
// ============================================================

#[cfg(test)]
mod property_tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        /// Any random bytes reduced to Ed25519 scalar are BN254 compatible
        #[test]
        fn prop_any_reduced_scalar_compatible(bytes in any::<[u8; 32]>()) {
            let scalar = Scalar::from_bytes_mod_order(bytes);
            prop_assert!(verify_scalar_bn254_compatible(&scalar));
        }
        
        /// Conversion never panics
        #[test]
        fn prop_conversion_never_panics(bytes in any::<[u8; 32]>()) {
            let scalar = Scalar::from_bytes_mod_order(bytes);
            let _ = ed25519_scalar_to_bn254_bytes(&scalar);
        }
    }
}

