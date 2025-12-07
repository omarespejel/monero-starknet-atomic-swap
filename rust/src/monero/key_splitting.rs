//! Atomic Swap Key Splitting for Monero
//!
//! This module implements the KEY SPLITTING approach for atomic swaps,
//! NOT CLSAG adaptor signatures. The key insight:
//!
//! - Split the key: x = x_partial + t
//! - Send T = t·G to Starknet with DLEQ proof
//! - When t is revealed, recover x = x_partial + t
//! - Create STANDARD Monero transaction with full key x
//!
//! This is the approach used by Serai DEX (audited by Cypher Stack).

use curve25519_dalek::{
    constants::ED25519_BASEPOINT_POINT as G,
    edwards::EdwardsPoint,
    scalar::Scalar,
};
use rand::rngs::OsRng;
use zeroize::{Zeroize, ZeroizeOnDrop};

/// Atomic swap key pair for Monero side.
/// 
/// Alice generates this, keeps `partial_key` secret, and sends
/// `adaptor_point` (T = t·G) to Starknet with a DLEQ proof.
/// 
/// Uses KEY SPLITTING approach: x = x_partial + t
/// When t is revealed on Starknet, recover x = x_partial + t
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct SwapKeyPair {
    /// Partial spend key - Alice keeps this secret
    pub partial_key: Scalar,
    /// Adaptor scalar t - will be revealed on Starknet
    pub adaptor_scalar: Scalar,
    /// Full spend key = partial_key + adaptor_scalar
    pub full_spend_key: Scalar,
    /// Adaptor point T = t·G (sent to Starknet)
    #[zeroize(skip)]
    pub adaptor_point: EdwardsPoint,
    /// Full public key P = x·G (Monero address is derived from this)
    #[zeroize(skip)]
    pub public_key: EdwardsPoint,
}

impl SwapKeyPair {
    /// Generate a new atomic swap key pair.
    pub fn generate() -> Self {
        let mut rng = OsRng;
        let partial_key = Scalar::random(&mut rng);
        let adaptor_scalar = Scalar::random(&mut rng);
        let full_spend_key = partial_key + adaptor_scalar;
        
        let adaptor_point = adaptor_scalar * G;
        let public_key = full_spend_key * G;
        
        Self {
            partial_key,
            adaptor_scalar,
            full_spend_key,
            adaptor_point,
            public_key,
        }
    }
    
    /// Recover full spend key when t is revealed from Starknet.
    pub fn recover(partial_key: Scalar, revealed_t: Scalar) -> Scalar {
        partial_key + revealed_t
    }
    
    /// Verify the key splitting math is correct.
    pub fn verify(&self) -> bool {
        // T + P_partial = P_full
        let partial_public = self.partial_key * G;
        self.adaptor_point + partial_public == self.public_key
    }
    
    /// Get adaptor scalar bytes (for hashlock computation).
    pub fn adaptor_scalar_bytes(&self) -> [u8; 32] {
        self.adaptor_scalar.to_bytes()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_key_splitting_math() {
        let keys = SwapKeyPair::generate();
        assert!(keys.verify(), "Key splitting: T + partial·G must equal X");
    }

    #[test]
    fn test_key_recovery() {
        let keys = SwapKeyPair::generate();
        let recovered = SwapKeyPair::recover(keys.partial_key, keys.adaptor_scalar);
        assert_eq!(recovered, keys.full_spend_key);
    }

    #[test]
    fn test_adaptor_point_derivation() {
        let keys = SwapKeyPair::generate();
        assert_eq!(keys.adaptor_point, keys.adaptor_scalar * G);
    }
    
    #[test]
    fn test_public_key_derivation() {
        let keys = SwapKeyPair::generate();
        assert_eq!(keys.public_key, keys.full_spend_key * G);
    }
}

