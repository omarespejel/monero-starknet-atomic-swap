//! Ed25519 → BN254 Scalar Compatibility Verification
//! 
//! SECURITY NOTE: Ed25519→BN254 Scalar Conversion
//!
//! Ed25519 scalar order: l ≈ 2^252
//! BN254 field prime:    p ≈ 2^254
//!
//! Conversion is SAFE because l < p (no modular reduction needed).
//! However, we verify this property explicitly to prevent future bugs
//! if curve parameters ever change or are misused.
//!
//! Reference: https://github.com/Lightprotocol/light-protocol/issues/237

use curve25519_dalek::scalar::Scalar;
use num_bigint::BigUint;
use num_traits::Num;

/// Ed25519 scalar group order: l = 2^252 + 27742317777372353535851937790883648493
pub const ED25519_ORDER: [u8; 32] = [
    0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58,
    0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
];

/// BN254 field prime: p = 21888242871839275222246405745257275088696311157297823662689037894645226208583
/// 
/// Note: This is the correct BN254 field prime. The bytes are in little-endian format.
pub const BN254_FIELD_PRIME: [u8; 32] = [
    0x47, 0xfd, 0x7c, 0xd8, 0x16, 0x8c, 0x20, 0x3c,
    0x8d, 0xca, 0x71, 0x68, 0x91, 0x6a, 0x81, 0x97,
    0x5d, 0x58, 0x81, 0x81, 0xb6, 0x45, 0x50, 0xb8,
    0x29, 0xa0, 0x31, 0xe1, 0x72, 0x4e, 0x64, 0x30,
];

/// Verify that an Ed25519 scalar is compatible with BN254 field operations.
/// 
/// Returns true if the scalar can be safely used in BN254 context.
/// This should ALWAYS return true for valid Ed25519 scalars, but we
/// check explicitly for defense in depth.
pub fn verify_scalar_bn254_compatible(scalar: &Scalar) -> bool {
    let scalar_bytes = scalar.to_bytes();
    let scalar_int = BigUint::from_bytes_le(&scalar_bytes);
    let bn254_prime = BigUint::from_bytes_le(&BN254_FIELD_PRIME);
    
    // Ed25519 scalars are always < Ed25519 order < BN254 prime
    scalar_int < bn254_prime
}

/// Convert Ed25519 scalar to bytes suitable for BN254 operations.
/// 
/// SAFETY: This function verifies compatibility before conversion.
/// Panics if scalar is somehow incompatible (should never happen).
pub fn ed25519_scalar_to_bn254_bytes(scalar: &Scalar) -> [u8; 32] {
    debug_assert!(
        verify_scalar_bn254_compatible(scalar),
        "Ed25519 scalar must be BN254 compatible"
    );
    
    // For valid Ed25519 scalars, bytes can be used directly
    // No modular reduction needed since Ed25519 order < BN254 prime
    scalar.to_bytes()
}

/// Verify the fundamental safety property at compile time (via const fn when stable)
/// and at runtime during tests.
pub fn verify_curve_order_relationship() -> bool {
    let ed25519_order = BigUint::from_bytes_le(&ED25519_ORDER);
    let bn254_prime = BigUint::from_bytes_le(&BN254_FIELD_PRIME);
    
    // CRITICAL: Ed25519 order MUST be less than BN254 prime
    ed25519_order < bn254_prime
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_curve_order_relationship() {
        assert!(
            verify_curve_order_relationship(),
            "CRITICAL: Ed25519 order must be < BN254 prime"
        );
    }
    
    #[test]
    fn test_constants_are_correct() {
        // Verify Ed25519 order matches known value
        let ed25519_order = BigUint::from_bytes_le(&ED25519_ORDER);
        let expected = BigUint::from_str_radix(
            "7237005577332262213973186563042994240857116359379907606001950938285454250989",
            10
        ).unwrap();
        assert_eq!(ed25519_order, expected, "Ed25519 order constant is wrong");
        
        // Verify BN254 prime matches known value
        let bn254_prime = BigUint::from_bytes_le(&BN254_FIELD_PRIME);
        let expected_prime = BigUint::from_str_radix(
            "21888242871839275222246405745257275088696311157297823662689037894645226208583",
            10
        ).unwrap();
        assert_eq!(bn254_prime, expected_prime, "BN254 prime constant is wrong");
    }
}

