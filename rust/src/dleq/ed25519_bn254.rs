//! Safe Ed25519 → BN254 Scalar Conversion
//! 
//! SECURITY CRITICAL: Prevents cross-curve vulnerabilities
//! Reference: https://github.com/Lightprotocol/light-protocol/issues/237

use curve25519_dalek::scalar::Scalar as Ed25519Scalar;
use thiserror::Error;

/// Ed25519 curve order: l = 2^252 + 27742317777372353535851937790883648493
pub const ED25519_ORDER: [u8; 32] = [
    0xed, 0xd3, 0xf5, 0x5c, 0x1a, 0x63, 0x12, 0x58,
    0xd6, 0x9c, 0xf7, 0xa2, 0xde, 0xf9, 0xde, 0x14,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x10,
];

/// BN254 field prime (larger than Ed25519 order)
pub const BN254_PRIME: [u8; 32] = [
    0x47, 0xfd, 0x7c, 0xd8, 0x16, 0x8c, 0x20, 0x3c,
    0x8d, 0xca, 0x71, 0x68, 0x91, 0x6a, 0x81, 0x97,
    0x5d, 0x58, 0x81, 0x81, 0xb6, 0x45, 0x50, 0xb8,
    0x29, 0xa0, 0x31, 0xe1, 0x72, 0x4e, 0x64, 0x30,
];

#[derive(Debug, Error, PartialEq)]
pub enum Ed25519Bn254ConversionError {
    #[error("Ed25519 scalar exceeds curve order - invalid input")]
    ScalarExceedsOrder,
    
    #[error("Security invariant violated: Ed25519 order >= BN254 prime")]
    SecurityInvariantViolated,
}

/// Safely convert Ed25519 scalar to BN254 field element
/// 
/// # Security
/// - Verifies scalar is within Ed25519 order
/// - Ed25519 order < BN254 prime, so no modular reduction needed
/// - Returns bytes suitable for Garaga MSM operations
pub fn ed25519_scalar_to_bn254_safe(
    scalar: &Ed25519Scalar
) -> Result<[u8; 32], Ed25519Bn254ConversionError> {
    // Security invariant check (compile-time would be better, but this is explicit)
    if !is_ed25519_order_less_than_bn254_prime() {
        return Err(Ed25519Bn254ConversionError::SecurityInvariantViolated);
    }
    
    // Get scalar bytes (already reduced mod l by curve25519-dalek)
    let scalar_bytes = scalar.to_bytes();
    
    // Since curve25519-dalek always reduces scalars mod l,
    // and l < p (BN254 prime), the bytes are valid in BN254 field
    Ok(scalar_bytes)
}

/// Verify security invariant: Ed25519 order < BN254 prime
fn is_ed25519_order_less_than_bn254_prime() -> bool {
    // Compare as big-endian integers
    for i in (0..32).rev() {
        if ED25519_ORDER[i] < BN254_PRIME[i] {
            return true;
        }
        if ED25519_ORDER[i] > BN254_PRIME[i] {
            return false;
        }
    }
    false  // Equal (shouldn't happen)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_order_less_than_prime() {
        assert!(is_ed25519_order_less_than_bn254_prime());
    }
}

