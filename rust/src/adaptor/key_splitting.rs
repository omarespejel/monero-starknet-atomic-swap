//! Monero key splitting for adaptor signatures.
//!
//! Splits a full Monero spend key into:
//! - `base_key`: The base component (kept secret until swap completes)
//! - `adaptor_scalar`: The scalar `t` that matches Cairo's hashlock

use curve25519_dalek::scalar::Scalar;
use rand::rngs::OsRng;
use rand::RngCore;

/// A split key pair: base key + adaptor scalar.
#[derive(Debug, Clone)]
pub struct KeyPair {
    /// Base component of the Monero spend key.
    pub base_key: Scalar,
    /// Adaptor scalar `t` that matches Cairo's hashlock.
    /// This is the same scalar used in: SHA-256(t) = H and t·G = T
    pub adaptor_scalar: Scalar,
}

/// Split a Monero spend key into base + adaptor components.
///
/// The adaptor scalar `t` is generated randomly and will be used to:
/// 1. Create the hashlock on Starknet: SHA-256(t) = H
/// 2. Create the adaptor point: t·G = T
/// 3. Create the adaptor signature on Monero
///
/// When `t` is revealed on Starknet, it can be used to finalize
/// the Monero signature and extract the full spend key.
///
/// # Arguments
///
/// * `full_key` - The full Monero spend key scalar
///
/// # Returns
///
/// A `KeyPair` containing the base key and adaptor scalar.
pub fn split_monero_key(full_key: Scalar) -> KeyPair {
    // Generate random adaptor scalar (same as generate_swap_secret does)
    let mut csprng = OsRng;
    let mut raw_bytes = [0u8; 32];
    csprng.fill_bytes(&mut raw_bytes);
    let adaptor_scalar = Scalar::from_bytes_mod_order(raw_bytes);

    // Base key = full_key - adaptor_scalar
    let base_key = full_key - adaptor_scalar;

    KeyPair {
        base_key,
        adaptor_scalar,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_splitting_reconstruction() {
        let full_key = Scalar::from_bytes_mod_order([1u8; 32]);
        let key_pair = split_monero_key(full_key);

        // Verify: base_key + adaptor_scalar == full_key
        let reconstructed = key_pair.base_key + key_pair.adaptor_scalar;
        assert_eq!(reconstructed, full_key);
    }

    #[test]
    fn test_key_splitting_different_adaptors() {
        let full_key = Scalar::from_bytes_mod_order([2u8; 32]);
        let pair1 = split_monero_key(full_key);
        let pair2 = split_monero_key(full_key);

        // Adaptor scalars should be different (random)
        assert_ne!(pair1.adaptor_scalar, pair2.adaptor_scalar);

        // But both should reconstruct to the same full key
        assert_eq!(pair1.base_key + pair1.adaptor_scalar, full_key);
        assert_eq!(pair2.base_key + pair2.adaptor_scalar, full_key);
    }
}
