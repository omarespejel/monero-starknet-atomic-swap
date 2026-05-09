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
#![allow(unused_assignments)]

use curve25519_dalek::{
    constants::ED25519_BASEPOINT_POINT as G, edwards::EdwardsPoint, scalar::Scalar,
};
use rand::{rngs::OsRng, RngCore};
use thiserror::Error;
use zeroize::{Zeroize, ZeroizeOnDrop, Zeroizing};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Error)]
pub enum KeySplitError {
    #[error("partial spend key reduced to zero")]
    ZeroPartialKey,
    #[error("adaptor secret reduced to zero")]
    ZeroAdaptorScalar,
}

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
    /// Raw adaptor secret bytes revealed on Starknet and hashed by Cairo.
    ///
    /// This is intentionally pre-reduction. Cairo checks SHA-256(raw bytes),
    /// while Monero key recovery interprets those bytes as a scalar modulo l.
    pub adaptor_secret_bytes: [u8; 32],
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

        loop {
            // Generate random scalars (v4.x API: use from_bytes_mod_order).
            let mut partial_bytes = [0u8; 32];
            rng.fill_bytes(&mut partial_bytes);

            let mut adaptor_secret_bytes = [0u8; 32];
            rng.fill_bytes(&mut adaptor_secret_bytes);

            let keys = Self::from_raw_scalars(partial_bytes, adaptor_secret_bytes);
            partial_bytes.zeroize();
            adaptor_secret_bytes.zeroize();

            if let Ok(keys) = keys {
                return keys;
            }
        }
    }

    /// Build a key pair from raw pre-reduction scalar bytes.
    ///
    /// `adaptor_secret_bytes` are the exact bytes that must be hashed in the
    /// Starknet hashlock and later revealed. They may differ from
    /// `adaptor_scalar.to_bytes()` after reduction modulo the ed25519 scalar
    /// order, so callers must not recompute the hashlock from canonical scalar
    /// bytes.
    pub fn from_raw_scalars(
        mut partial_key_bytes: [u8; 32],
        mut adaptor_secret_bytes: [u8; 32],
    ) -> Result<Self, KeySplitError> {
        let partial_key = Scalar::from_bytes_mod_order(partial_key_bytes);
        partial_key_bytes.zeroize();
        if partial_key == Scalar::ZERO {
            adaptor_secret_bytes.zeroize();
            return Err(KeySplitError::ZeroPartialKey);
        }

        let adaptor_scalar = Scalar::from_bytes_mod_order(adaptor_secret_bytes);
        if adaptor_scalar == Scalar::ZERO {
            adaptor_secret_bytes.zeroize();
            return Err(KeySplitError::ZeroAdaptorScalar);
        }

        let mut stored_adaptor_secret_bytes = adaptor_secret_bytes;
        adaptor_secret_bytes.zeroize();

        let full_spend_key = partial_key + adaptor_scalar;
        let adaptor_point = adaptor_scalar * G;
        let public_key = full_spend_key * G;

        let keys = Self {
            partial_key,
            adaptor_scalar,
            adaptor_secret_bytes: stored_adaptor_secret_bytes,
            full_spend_key,
            adaptor_point,
            public_key,
        };
        stored_adaptor_secret_bytes.zeroize();

        Ok(keys)
    }

    /// Recover full spend key when t is revealed from Starknet.
    ///
    /// **Security**: Uses constant-time scalar addition (curve25519-dalek guarantees).
    /// The partial_key is wrapped in `Zeroizing` for memory safety, and the result
    /// is also wrapped to ensure automatic zeroization when dropped.
    ///
    /// # Arguments
    ///
    /// * `partial_key` - The partial spend key (wrapped in Zeroizing for memory safety)
    /// * `revealed_t` - The adaptor scalar t revealed on Starknet
    ///
    /// # Returns
    ///
    /// The full spend key `x = x_partial + t` wrapped in `Zeroizing` for automatic cleanup.
    ///
    /// # Security Properties
    ///
    /// - **Constant-time**: Scalar addition is constant-time (no secret-dependent branches)
    /// - **Memory safety**: Result is automatically zeroed when dropped
    /// - **DLP security**: Given `T = t·G` on Starknet, recovering `t` requires solving DLP
    pub fn recover(partial_key: Zeroizing<Scalar>, revealed_t: Scalar) -> Zeroizing<Scalar> {
        // Constant-time scalar addition (curve25519-dalek guarantees)
        // No secret-dependent branches or memory accesses
        Zeroizing::new(*partial_key + revealed_t)
    }

    /// Recover full spend key when t is revealed from Starknet (non-zeroizing version).
    ///
    /// **Note**: This is a convenience method for cases where zeroization is not needed.
    /// Prefer `recover()` for production code to ensure memory safety.
    ///
    /// # Arguments
    ///
    /// * `partial_key` - The partial spend key
    /// * `revealed_t` - The adaptor scalar t revealed on Starknet
    ///
    /// # Returns
    ///
    /// The full spend key `x = x_partial + t`
    pub fn recover_plain(partial_key: Scalar, revealed_t: Scalar) -> Scalar {
        partial_key + revealed_t
    }

    /// Verify the key splitting math is correct.
    pub fn verify(&self) -> bool {
        // T + P_partial = P_full
        let partial_public = self.partial_key * G;
        self.adaptor_point + partial_public == self.public_key
    }

    /// Get raw adaptor secret bytes for Starknet hashlock computation.
    pub fn adaptor_secret_bytes(&self) -> [u8; 32] {
        self.adaptor_secret_bytes
    }

    /// Get raw adaptor secret bytes for Starknet hashlock computation.
    ///
    /// Kept for existing callers. Despite the legacy name, this returns the
    /// pre-reduction bytes that Cairo hashes and expects to be revealed, not
    /// `adaptor_scalar.to_bytes()`.
    pub fn adaptor_scalar_bytes(&self) -> [u8; 32] {
        self.adaptor_secret_bytes()
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
        let partial_key_zeroizing = Zeroizing::new(keys.partial_key);
        let recovered = SwapKeyPair::recover(partial_key_zeroizing, keys.adaptor_scalar);
        assert_eq!(*recovered, keys.full_spend_key);
    }

    #[test]
    fn test_key_recovery_plain() {
        let keys = SwapKeyPair::generate();
        let recovered = SwapKeyPair::recover_plain(keys.partial_key, keys.adaptor_scalar);
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

    #[test]
    fn test_raw_adaptor_bytes_preserved_for_hashlock() {
        let partial_bytes = [0x11u8; 32];
        let adaptor_secret_bytes = [0xffu8; 32];

        let keys = SwapKeyPair::from_raw_scalars(partial_bytes, adaptor_secret_bytes)
            .expect("valid non-zero reduced scalars");

        assert!(keys.verify());
        assert_eq!(keys.adaptor_secret_bytes(), adaptor_secret_bytes);
        assert_eq!(keys.adaptor_scalar_bytes(), adaptor_secret_bytes);
        assert_ne!(
            keys.adaptor_scalar.to_bytes(),
            keys.adaptor_secret_bytes(),
            "raw hashlock preimage must be kept even when scalar reduction changes bytes"
        );
    }

    #[test]
    fn test_zero_reduced_scalars_rejected() {
        let valid = [0x11u8; 32];

        assert!(
            matches!(
                SwapKeyPair::from_raw_scalars([0u8; 32], valid),
                Err(KeySplitError::ZeroPartialKey)
            ),
            "zero partial key must be rejected"
        );
        assert!(
            matches!(
                SwapKeyPair::from_raw_scalars(valid, [0u8; 32]),
                Err(KeySplitError::ZeroAdaptorScalar)
            ),
            "zero adaptor scalar must be rejected"
        );
    }

    /// Test recovery across representative scalar values.
    ///
    /// `recover()` uses curve25519-dalek scalar addition, which is implemented
    /// without secret-dependent branches. A wall-clock timing assertion is too
    /// noisy for unit tests because scheduler/cache jitter can dominate a single
    /// scalar addition, so this test keeps the CI check deterministic and leaves
    /// timing analysis to dedicated benchmarks.
    #[test]
    fn test_recover_edge_vectors() {
        let vectors = [
            ([1u8; 32], [2u8; 32]),
            ([0x7fu8; 32], [0x80u8; 32]),
            ([0xffu8; 32], [0x01u8; 32]),
            ([0x42u8; 32], [0x99u8; 32]),
        ];

        for (partial_bytes, adaptor_bytes) in vectors {
            let partial_key = Scalar::from_bytes_mod_order(partial_bytes);
            let adaptor_scalar = Scalar::from_bytes_mod_order(adaptor_bytes);
            let expected = partial_key + adaptor_scalar;

            let recovered = SwapKeyPair::recover(Zeroizing::new(partial_key), adaptor_scalar);

            assert_eq!(*recovered, expected);
        }
    }
}
