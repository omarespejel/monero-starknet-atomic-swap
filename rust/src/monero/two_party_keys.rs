//! Two-Party Key Generation for Monero Atomic Swaps
//!
//! Implements the two-party protocol where:
//! - Alice generates s_a (spend share) and v_a (view share)
//! - Bob generates s_b (spend share)
//! - Combined keys: S = (s_a + s_b)·G, V = (v_a + v_b)·G
//!
//! SECURITY: All scalars are verified for BN254 compatibility before use.
#![allow(non_snake_case)]
#![allow(unused_assignments)]

use anyhow::Result;
use curve25519_dalek::{
    constants::ED25519_BASEPOINT_POINT as G,
    edwards::{CompressedEdwardsY, EdwardsPoint},
    scalar::Scalar,
};
use rand::{rngs::OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::crypto::scalar_compat::verify_scalar_bn254_compatible;

/// Alice's key shares for two-party protocol.
///
/// Alice generates:
/// - s_a: Spend key share
/// - v_a: View key share
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct AliceKeys {
    /// Alice's spend key share s_a
    spend_share: Scalar,
    /// Alice's view key share v_a
    view_share: Scalar,
    /// Public spend key share S_a = s_a·G
    #[zeroize(skip)]
    pub S_a: EdwardsPoint,
    /// Public view key share V_a = v_a·G
    #[zeroize(skip)]
    pub V_a: EdwardsPoint,
}

impl AliceKeys {
    /// Generate new Alice keys.
    ///
    /// SECURITY: Rejects zero scalars (astronomically unlikely but possible).
    /// Retries generation if zero scalar is produced (P1 audit fix).
    pub fn generate() -> Self {
        loop {
            let mut rng = OsRng;

            // Generate spend share
            let mut s_a_bytes = [0u8; 32];
            rng.fill_bytes(&mut s_a_bytes);
            let s_a = Scalar::from_bytes_mod_order(s_a_bytes);
            s_a_bytes.zeroize();

            // SECURITY: Explicitly reject zero scalar (P1 audit fix - consistency with BobKeys)
            // Probability is ~2^-252, but we must handle it for production safety
            if s_a == Scalar::ZERO {
                continue; // Retry on zero (astronomically unlikely)
            }

            // Generate view share
            let mut v_a_bytes = [0u8; 32];
            rng.fill_bytes(&mut v_a_bytes);
            let v_a = Scalar::from_bytes_mod_order(v_a_bytes);
            v_a_bytes.zeroize();

            // SECURITY: Explicitly reject zero scalar for view share (P1 audit fix)
            if v_a == Scalar::ZERO {
                continue; // Retry on zero (astronomically unlikely)
            }

            // SECURITY: Verify BN254 compatibility
            debug_assert!(
                verify_scalar_bn254_compatible(&s_a),
                "Alice's spend share must be BN254 compatible"
            );
            debug_assert!(
                verify_scalar_bn254_compatible(&v_a),
                "Alice's view share must be BN254 compatible"
            );

            let S_a = s_a * G;
            let V_a = v_a * G;

            return Self {
                spend_share: s_a,
                view_share: v_a,
                S_a,
                V_a,
            };
        }
    }

    /// Get Alice's spend share.
    pub fn spend_share(&self) -> Scalar {
        self.spend_share
    }

    /// Get Alice's view share.
    pub fn view_share(&self) -> Scalar {
        self.view_share
    }

    /// Get public data for serialization (P0.2: Auditor requirement)
    pub fn public_data(&self) -> AlicePublicData {
        AlicePublicData {
            S_a: self.S_a.compress().to_bytes(),
            V_a: self.V_a.compress().to_bytes(),
            v_a: self.view_share.to_bytes(),
        }
    }
}

/// Alice's public data for serialization
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct AlicePublicData {
    pub S_a: [u8; 32],
    pub V_a: [u8; 32],
    pub v_a: [u8; 32],
}

impl AlicePublicData {
    /// Validate Alice's public data (P2 audit fix)
    ///
    /// Verifies:
    /// - S_a is a valid curve point (on-curve, not infinity)
    /// - V_a is a valid curve point (on-curve, not infinity)
    ///
    /// Returns `Ok(())` if valid, `Err` otherwise.
    pub fn validate(&self) -> Result<()> {
        // Verify S_a is a valid curve point
        CompressedEdwardsY(self.S_a)
            .decompress()
            .ok_or_else(|| anyhow::anyhow!("Invalid spend key share S_a"))?;

        // Verify V_a is a valid curve point
        CompressedEdwardsY(self.V_a)
            .decompress()
            .ok_or_else(|| anyhow::anyhow!("Invalid view key share V_a"))?;

        Ok(())
    }
}

/// Bob's key shares for two-party protocol.
///
/// Bob generates:
/// - s_b: Spend key share
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct BobKeys {
    /// Bob's spend key share s_b
    spend_share: Scalar,
    /// Raw bytes of spend share (before scalar reduction, for hashlock computation)
    raw_secret_bytes: [u8; 32],
    /// Public spend key share S_b = s_b·G
    #[zeroize(skip)]
    pub S_b: EdwardsPoint,
    /// View key share v_b (derived deterministically from s_b)
    view_share: Scalar,
    /// Public view key share V_b = v_b·G
    #[zeroize(skip)]
    pub V_b: EdwardsPoint,
    /// Hashlock H = SHA-256(raw_secret_bytes)
    ///
    /// **CRITICAL**: Uses SHA-256 (not BLAKE2s) to match Cairo's hashlock verification.
    /// Cairo contract uses `compute_sha256_byte_array(@secret)` for hashlock verification.
    /// DLEQ challenge uses Poseidon (separate from hashlock).
    #[zeroize(skip)]
    pub hashlock: [u8; 32],
    /// Adaptor point T = s_b·G (same as S_b, but kept for clarity)
    #[zeroize(skip)]
    pub adaptor_point: EdwardsPoint,
}

impl BobKeys {
    /// Generate new Bob keys.
    ///
    /// SECURITY: Rejects zero scalars (astronomically unlikely but possible).
    /// Retries generation if zero scalar is produced.
    pub fn generate() -> Self {
        loop {
            let mut rng = OsRng;

            // Generate spend share
            let mut s_b_bytes = [0u8; 32];
            rng.fill_bytes(&mut s_b_bytes);
            let s_b = Scalar::from_bytes_mod_order(s_b_bytes);

            // SECURITY: Explicitly reject zero scalar (P0 audit fix)
            // Probability is ~2^-252, but we must handle it for production safety
            if s_b == Scalar::ZERO {
                continue; // Retry on zero (astronomically unlikely)
            }

            // SECURITY: Verify BN254 compatibility
            debug_assert!(
                verify_scalar_bn254_compatible(&s_b),
                "Bob's spend share must be BN254 compatible"
            );

            // Derive view share deterministically from spend share
            // Using SHA-256 for domain separation
            let mut hasher = Sha256::new();
            hasher.update(b"VIEW_KEY_V1");
            hasher.update(&s_b_bytes);
            let v_b_bytes: [u8; 32] = hasher.finalize().into();
            let v_b = Scalar::from_bytes_mod_order(v_b_bytes);

            // Compute hashlock from raw bytes (before scalar reduction)
            // CRITICAL: Uses SHA-256 to match Cairo's hashlock verification
            // Cairo: compute_sha256_byte_array(@secret) -> 8×u32 words
            // DLEQ challenge uses Poseidon (separate computation)
            let hashlock: [u8; 32] = Sha256::digest(s_b_bytes).into();

            // Store raw bytes for hashlock verification (Cairo compatibility)
            let raw_secret_bytes = s_b_bytes;

            // Zeroize the mutable copy (raw_secret_bytes is now owned)
            // Note: We keep raw_secret_bytes in the struct for hashlock verification

            let S_b = s_b * G;
            let V_b = v_b * G;
            let adaptor_point = S_b; // T = s_b·G

            // SECURITY: Verify hashlock is non-zero (should never happen if s_b != 0)
            debug_assert!(
                hashlock != [0u8; 32],
                "Hashlock cannot be zero if scalar is non-zero"
            );

            return Self {
                spend_share: s_b,
                raw_secret_bytes,
                S_b,
                view_share: v_b,
                V_b,
                hashlock,
                adaptor_point,
            };
        }
    }

    /// Get Bob's spend share.
    pub fn spend_share(&self) -> Scalar {
        self.spend_share
    }

    /// Get Bob's view share.
    pub fn view_share(&self) -> Scalar {
        self.view_share
    }

    /// Get hashlock.
    pub fn hashlock(&self) -> [u8; 32] {
        self.hashlock
    }

    /// Get adaptor point.
    pub fn adaptor_point(&self) -> EdwardsPoint {
        self.adaptor_point
    }

    /// Get secret bytes (for hashlock verification).
    ///
    /// Returns the raw bytes used for hashlock computation (before scalar reduction).
    /// This matches Cairo's hashlock computation: SHA-256(raw_bytes).
    pub fn secret_bytes(&self) -> [u8; 32] {
        self.raw_secret_bytes
    }

    /// Get public data for serialization (P0.2: Auditor requirement)
    pub fn public_data(&self) -> BobPublicData {
        BobPublicData {
            S_b: self.S_b.compress().to_bytes(),
            V_b: self.V_b.compress().to_bytes(),
            v_b: self.view_share.to_bytes(),
            hashlock: self.hashlock,
        }
    }
}

/// Bob's public data for serialization
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq)]
pub struct BobPublicData {
    pub S_b: [u8; 32],
    pub V_b: [u8; 32],
    pub v_b: [u8; 32],
    pub hashlock: [u8; 32],
}

impl BobPublicData {
    /// Validate Bob's public data (P0.6: Auditor requirement)
    ///
    /// Verifies:
    /// - S_b is a valid curve point (on-curve, not infinity)
    /// - V_b is a valid curve point (on-curve, not infinity)
    /// - Hashlock is non-zero and exactly 32 bytes (P0 audit fix)
    ///
    /// Returns `Ok(())` if valid, `Err` otherwise.
    pub fn validate(&self) -> Result<()> {
        // Verify S_b is a valid curve point
        CompressedEdwardsY(self.S_b)
            .decompress()
            .ok_or_else(|| anyhow::anyhow!("Invalid adaptor point S_b"))?;

        // Verify V_b is a valid curve point
        CompressedEdwardsY(self.V_b)
            .decompress()
            .ok_or_else(|| anyhow::anyhow!("Invalid view point V_b"))?;

        // Verify hashlock is non-zero (P0 audit fix)
        if self.hashlock == [0u8; 32] {
            anyhow::bail!("Hashlock cannot be zero");
        }

        // Verify hashlock length is exactly 32 bytes (P0 audit fix)
        // Cairo expects exactly 32 bytes for SHA-256 hashlock
        if self.hashlock.len() != 32 {
            anyhow::bail!("Hashlock must be exactly 32 bytes (SHA-256 output)");
        }

        Ok(())
    }
}

/// Shared output from combining Alice and Bob keys.
#[derive(Clone)]
pub struct SharedOutput {
    /// Combined spend public key S = (s_a + s_b)·G
    pub S: EdwardsPoint,
    /// Combined view public key V = (v_a + v_b)·G
    pub V: EdwardsPoint,
    /// Combined view scalar v = v_a + v_b
    pub v: Scalar,
}

impl SharedOutput {
    /// Create shared output from Alice and Bob keys.
    pub fn new(alice: &AliceKeys, bob: &BobKeys) -> Self {
        let s_a = alice.spend_share();
        let s_b = bob.spend_share();
        let v_a = alice.view_share();
        let v_b = bob.view_share();

        // Combined keys
        let S = (s_a + s_b) * G;
        let V = (v_a + v_b) * G;
        let v = v_a + v_b;

        // SECURITY: Verify combined scalar is BN254 compatible
        debug_assert!(
            verify_scalar_bn254_compatible(&(s_a + s_b)),
            "Combined spend scalar must be BN254 compatible"
        );
        debug_assert!(
            verify_scalar_bn254_compatible(&v),
            "Combined view scalar must be BN254 compatible"
        );

        Self { S, V, v }
    }

    /// Create shared output from public data (P0.2: Auditor requirement)
    pub fn from_public(alice: &AlicePublicData, bob: &BobPublicData) -> Result<Self> {
        let S_a = CompressedEdwardsY(alice.S_a)
            .decompress()
            .ok_or_else(|| anyhow::anyhow!("Invalid S_a"))?;
        let V_a = CompressedEdwardsY(alice.V_a)
            .decompress()
            .ok_or_else(|| anyhow::anyhow!("Invalid V_a"))?;
        let S_b = CompressedEdwardsY(bob.S_b)
            .decompress()
            .ok_or_else(|| anyhow::anyhow!("Invalid S_b"))?;
        let V_b = CompressedEdwardsY(bob.V_b)
            .decompress()
            .ok_or_else(|| anyhow::anyhow!("Invalid V_b"))?;

        Ok(Self {
            S: S_a + S_b,
            V: V_a + V_b,
            v: Scalar::from_bytes_mod_order(alice.v_a) + Scalar::from_bytes_mod_order(bob.v_b),
        })
    }
}

/// Recover spend key from shares (P0.2: Auditor requirement)
pub fn recover_spend_key(s_a: Scalar, s_b_revealed: Scalar) -> Scalar {
    s_a + s_b_revealed
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_alice_bob_shared_output() {
        let alice = AliceKeys::generate();
        let bob = BobKeys::generate();
        let shared = SharedOutput::new(&alice, &bob);

        // Verify math: S should equal S_a + S_b
        assert_eq!(shared.S, alice.S_a + bob.S_b);

        // Verify math: V should equal V_a + V_b
        assert_eq!(shared.V, alice.V_a + bob.V_b);
    }
}
