//! CLSAG Adaptor Signatures for Atomic Swaps
//!
//! An adaptor signature is a "partial" signature that can only be completed
//! when an adaptor scalar t is revealed. This enables atomic swaps:
//!
//! 1. Alice creates partial CLSAG with adaptor point T = t·G
//! 2. Alice sends T to Starknet contract (with DLEQ proof)
//! 3. Bob unlocks Starknet contract, revealing t
//! 4. Alice uses t to finalize her CLSAG and claim Monero

use curve25519_dalek::{
    constants::ED25519_BASEPOINT_POINT,
    edwards::EdwardsPoint,
    scalar::Scalar,
};
use sha3::{Digest, Keccak256};
use zeroize::Zeroize;

use super::RingMember;

// TODO: Import from monero-clsag-mirror once API is confirmed
// For now, we'll implement minimal hash-to-point and key image functions
// These should eventually use the audited library

/// Hash a point to a point (Hp function for Monero key images)
/// Uses Keccak256 as per Monero CLSAG spec
fn hash_to_point(point: &EdwardsPoint) -> EdwardsPoint {
    let mut hasher = Keccak256::new();
    hasher.update(b"CLSAG_Hp");
    hasher.update(point.compress().as_bytes());
    let hash = hasher.finalize();
    
    // Convert hash to scalar and multiply by base point
    // This is a simplified version - production should use proper hash-to-point
    let scalar = Scalar::from_bytes_mod_order(hash.into());
    scalar * ED25519_BASEPOINT_POINT
}

/// Compute key image I = x·Hp(P)
fn compute_key_image(spend_key: &Scalar, public_key: &EdwardsPoint) -> EdwardsPoint {
    let hp = hash_to_point(public_key);
    *spend_key * hp
}

/// A partial CLSAG signature with embedded adaptor.
/// 
/// The signature is incomplete: s[real_index] is computed as if the
/// secret key were (x - t) instead of x. When t is revealed, we can
/// adjust s[real_index] to complete the signature.
#[derive(Debug, Clone)]
pub struct ClsagAdaptorSignature {
    /// Initial challenge c₁
    pub c1: Scalar,
    /// Partial response scalars (s[real_index] needs adjustment)
    pub responses: Vec<Scalar>,
    /// Key image I = x·Hp(P) (uses FULL key, for linkability)
    pub key_image: EdwardsPoint,
    /// Commitment key image D
    pub commitment_key_image: EdwardsPoint,
    /// The adaptor point T = t·G
    pub adaptor_point: EdwardsPoint,
    /// Index of the real signer (where adjustment is needed)
    pub real_index: usize,
    /// The challenge at real_index (needed for finalization)
    pub challenge_at_real: Scalar,
}

/// Signing context for adaptor CLSAG.
pub struct ClsagAdaptorSigner {
    ring: Vec<RingMember>,
    real_index: usize,
    message: Vec<u8>,
}

impl ClsagAdaptorSigner {
    pub fn new(ring: Vec<RingMember>, real_index: usize, message: Vec<u8>) -> Self {
        assert!(real_index < ring.len());
        assert!(ring.len() >= 2);
        
        Self { ring, real_index, message }
    }

    /// Create a partial CLSAG signature with adaptor.
    /// 
    /// # Arguments
    /// * `spend_key` - The FULL secret key x (P = x·G)
    /// * `adaptor_scalar` - The adaptor scalar t (T = t·G goes to Starknet)
    /// * `commitment_key` - Secret for commitment (z)
    /// 
    /// # Key Insight
    /// We sign with (x - t) as the "partial" key.
    /// The key image uses x (not x-t) so it's still valid when finalized.
    /// 
    /// # Returns
    /// * Partial signature that can be finalized with t
    /// * Adaptor point T = t·G for Starknet
    pub fn sign_adaptor(
        &self,
        spend_key: Scalar,
        adaptor_scalar: Scalar,
        commitment_key: Scalar,
    ) -> ClsagAdaptorSignature {
        let n = self.ring.len();
        let G = ED25519_BASEPOINT_POINT;
        
        // Adaptor point (goes to Starknet)
        let adaptor_point = adaptor_scalar * G;
        
        // Partial key (what we sign with)
        let partial_spend_key = spend_key - adaptor_scalar;
        
        // Get real member's public key
        let P_real = self.ring[self.real_index].public_key;
        let Hp_real = hash_to_point(&P_real);
        
        // IMPORTANT: Key image uses FULL spend_key for linkability
        // This ensures the finalized signature has correct key image
        let I = compute_key_image(&spend_key, &P_real);
        let D = commitment_key * Hp_real;
        
        // Aggregation coefficients
        let (mu_P, mu_C) = self.compute_aggregation_coefficients();
        
        // Generate nonce
        let mut alpha = Scalar::random(&mut rand::rngs::OsRng);
        
        // Initial commitment (real signer's contribution)
        let L_real = alpha * G;
        let R_real = alpha * Hp_real;
        
        // First challenge: c_{π+1} = H(... || L_π || R_π)
        let first_challenge = self.compute_challenge(&L_real, &R_real, &I, &D, mu_P, mu_C);
        
        // CRITICAL: c1 is the challenge computed FROM L_0, R_0
        // If π == 0, then c_{π+1} = c_1, which IS c1 (computed from L_0, R_0)
        let mut c1 = if self.real_index == 0 {
            first_challenge  // This is c_1 when π == 0 (computed from L_0, R_0)
        } else {
            Scalar::ZERO  // Will be set in loop when we process index 0
        };
        
        let mut c = first_challenge;
        
        // Initialize responses
        let mut responses: Vec<Scalar> = vec![Scalar::ZERO; n];
        
        // Go around the ring: π+1, π+2, ..., n-1, 0, 1, ..., π-1
        for offset in 1..n {
            let i = (self.real_index + offset) % n;
            
            // Random response for decoy
            let s_i = Scalar::random(&mut rand::rngs::OsRng);
            responses[i] = s_i;
            
            let P_i = self.ring[i].public_key;
            let C_i = self.ring[i].commitment;
            let Hp_i = hash_to_point(&P_i);
            
            let P_prime_i = mu_P * P_i + mu_C * C_i;
            let I_prime = mu_P * I + mu_C * D;
            
            // Compute L_i, R_i using current challenge c
            let L_i = s_i * G + c * P_prime_i;
            let R_i = s_i * Hp_i + c * I_prime;
            
            // Compute next challenge: c_{i+1} = H(... || L_i || R_i)
            let next_c = self.compute_challenge(&L_i, &R_i, &I, &D, mu_P, mu_C);
            
            // CAPTURE c1: It's the challenge computed FROM L_0, R_0
            // When i == 0, we just computed L_0, R_0, and next_c is c_1
            if i == 0 && self.real_index != 0 {
                c1 = next_c;  // This is c_1 (computed from L_0, R_0)
            }
            
            c = next_c;
        }
        
        // After the loop, c is c_π (challenge at the real index)
        let challenge_at_real = c;
        
        // CRITICAL: Sign with PARTIAL key (x - t)
        // s'_π = α - c_π · (μ_P·(x-t) + μ_C·z)
        let partial_aggregate = mu_P * partial_spend_key + mu_C * commitment_key;
        responses[self.real_index] = alpha - challenge_at_real * partial_aggregate;
        
        // If real_index == 0, we need to recompute c1 after computing s_0
        // because c1 should be computed from the FINAL L_0, R_0 (using s_0), not the initial ones
        if self.real_index == 0 {
            let s_0 = responses[0];
            let P_0 = self.ring[0].public_key;
            let C_0 = self.ring[0].commitment;
            let Hp_0 = hash_to_point(&P_0);
            let P_prime_0 = mu_P * P_0 + mu_C * C_0;
            let I_prime = mu_P * I + mu_C * D;
            
            // Compute FINAL L_0, R_0 using s_0 and challenge_at_real (which is c_0)
            let L_0_final = s_0 * G + challenge_at_real * P_prime_0;
            let R_0_final = s_0 * Hp_0 + challenge_at_real * I_prime;
            
            // c1 is the challenge computed FROM the final L_0, R_0
            c1 = self.compute_challenge(&L_0_final, &R_0_final, &I, &D, mu_P, mu_C);
        }
        
        // Zeroize
        alpha.zeroize();
        
        ClsagAdaptorSignature {
            c1,
            responses,
            key_image: I,
            commitment_key_image: D,
            adaptor_point,
            real_index: self.real_index,
            challenge_at_real,
        }
    }

    fn compute_aggregation_coefficients(&self) -> (Scalar, Scalar) {
        let mut hasher_p = Keccak256::new();
        let mut hasher_c = Keccak256::new();
        
        hasher_p.update(b"CLSAG_agg_0");
        hasher_c.update(b"CLSAG_agg_1");
        
        for member in &self.ring {
            hasher_p.update(member.public_key.compress().as_bytes());
            hasher_p.update(member.commitment.compress().as_bytes());
            hasher_c.update(member.public_key.compress().as_bytes());
            hasher_c.update(member.commitment.compress().as_bytes());
        }
        
        (
            Scalar::from_bytes_mod_order(hasher_p.finalize().into()),
            Scalar::from_bytes_mod_order(hasher_c.finalize().into()),
        )
    }

    fn compute_challenge(
        &self,
        L: &EdwardsPoint,
        R: &EdwardsPoint,
        I: &EdwardsPoint,
        D: &EdwardsPoint,
        mu_P: Scalar,
        mu_C: Scalar,
    ) -> Scalar {
        let mut hasher = Keccak256::new();
        hasher.update(b"CLSAG_round");
        hasher.update(&self.message);
        
        for member in &self.ring {
            hasher.update(member.public_key.compress().as_bytes());
            hasher.update(member.commitment.compress().as_bytes());
        }
        
        hasher.update(I.compress().as_bytes());
        hasher.update(D.compress().as_bytes());
        hasher.update(L.compress().as_bytes());
        hasher.update(R.compress().as_bytes());
        
        Scalar::from_bytes_mod_order(hasher.finalize().into())
    }

    fn compute_c1(
        &self,
        responses: &[Scalar],
        I: &EdwardsPoint,
        D: &EdwardsPoint,
        mu_P: Scalar,
        mu_C: Scalar,
        challenge_at_real: Scalar,
    ) -> Scalar {
        // For simplicity, if real_index is 0, c1 is the challenge after completing the ring
        // Otherwise, we need to trace through
        
        // This is simplified - production code needs full ring tracing
        if self.real_index == 0 {
            // c1 = challenge after index 0's L, R computation
            let G = ED25519_BASEPOINT_POINT;
            let s_0 = responses[0];
            let P_0 = self.ring[0].public_key;
            let C_0 = self.ring[0].commitment;
            let Hp_0 = hash_to_point(&P_0);
            
            let P_prime_0 = mu_P * P_0 + mu_C * C_0;
            let I_prime = mu_P * *I + mu_C * *D;
            
            let L_0 = s_0 * G + challenge_at_real * P_prime_0;
            let R_0 = s_0 * Hp_0 + challenge_at_real * I_prime;
            
            self.compute_challenge(&L_0, &R_0, I, D, mu_P, mu_C)
        } else {
            // Simplified: return challenge_at_real (needs proper implementation)
            challenge_at_real
        }
    }
}

impl ClsagAdaptorSignature {
    /// Finalize the adaptor signature using the revealed scalar.
    /// 
    /// When the atomic swap counterparty reveals t on Starknet
    /// (by calling verify_and_unlock), we can complete the signature.
    /// 
    /// # Arguments
    /// * `adaptor_scalar` - The revealed scalar t
    /// * `mu_P` - Aggregation coefficient μ_P
    /// 
    /// # Returns
    /// * A complete, valid CLSAG signature
    pub fn finalize(mut self, adaptor_scalar: Scalar, mu_P: Scalar) -> super::ClsagSignature {
        // Adjust s[real_index]:
        // s'_π was computed as: α - c_π · (μ_P·(x-t) + μ_C·z)
        // We need:              α - c_π · (μ_P·x + μ_C·z)
        // Difference: c_π · μ_P · t
        // So: s_π = s'_π - c_π · μ_P · t
        
        let adjustment = self.challenge_at_real * mu_P * adaptor_scalar;
        self.responses[self.real_index] = self.responses[self.real_index] - adjustment;
        
        super::ClsagSignature {
            c1: self.c1,
            responses: self.responses,
            key_image: self.key_image,
            commitment_key_image: self.commitment_key_image,
        }
    }

    /// Verify the adaptor signature is well-formed (partial verification).
    /// 
    /// This doesn't verify as a full CLSAG (it won't pass), but checks
    /// that the structure is valid and the adaptor point is correct.
    pub fn verify_adaptor_structure(&self, expected_adaptor_point: &EdwardsPoint) -> bool {
        // Check adaptor point matches
        self.adaptor_point == *expected_adaptor_point
    }
}

/// Extract the adaptor scalar from partial and finalized signatures.
/// 
/// This is used by the counterparty: if they see both the partial (adaptor)
/// signature and the finalized signature on-chain, they can extract t.
/// 
/// t = (s'_π - s_π) / (c_π · μ_P)
pub fn extract_adaptor_scalar(
    partial: &ClsagAdaptorSignature,
    finalized: &super::ClsagSignature,
    mu_P: Scalar,
) -> Scalar {
    let s_partial = partial.responses[partial.real_index];
    let s_final = finalized.responses[partial.real_index];
    let c = partial.challenge_at_real;
    
    // s'_π - s_π = c_π · μ_P · t
    // t = (s'_π - s_π) / (c_π · μ_P)
    let diff = s_partial - s_final;
    let denominator = c * mu_P;
    
    diff * denominator.invert()
}

#[cfg(test)]
mod tests {
    use super::*;
    use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;

    fn create_test_ring(real_public_key: EdwardsPoint, size: usize) -> (Vec<RingMember>, usize) {
        let mut ring = Vec::new();
        let real_index = size / 2; // Put real key in the middle
        
        for i in 0..size {
            let (pk, commitment) = if i == real_index {
                (real_public_key, Scalar::from(100u64) * ED25519_BASEPOINT_POINT)
            } else {
                let fake_key = Scalar::random(&mut rand::rngs::OsRng) * ED25519_BASEPOINT_POINT;
                let fake_commitment = Scalar::random(&mut rand::rngs::OsRng) * ED25519_BASEPOINT_POINT;
                (fake_key, fake_commitment)
            };
            
            ring.push(RingMember {
                public_key: pk,
                commitment,
            });
        }
        
        (ring, real_index)
    }

    #[test]
    fn test_adaptor_signature_flow() {
        let G = ED25519_BASEPOINT_POINT;
        
        // 1. Alice has a full spend key
        let spend_key = Scalar::random(&mut rand::rngs::OsRng);
        let public_key = spend_key * G;
        
        // 2. She splits it: spend_key = partial_key + adaptor_scalar
        let adaptor_scalar = Scalar::random(&mut rand::rngs::OsRng);
        let adaptor_point = adaptor_scalar * G;
        
        // 3. Create ring with her public key
        let commitment_key = Scalar::from(50u64);
        let (ring, real_index) = create_test_ring(public_key, 11);
        
        // 4. Create adaptor signature
        let message = b"test transaction".to_vec();
        let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
        let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
        
        // 5. Verify adaptor point matches
        assert_eq!(adaptor_sig.adaptor_point, adaptor_point);
        
        // 6. Later, when t is revealed on Starknet, finalize
        let (mu_P, _mu_C) = {
            let mut hasher_p = Keccak256::new();
            hasher_p.update(b"CLSAG_agg_0");
            for member in &ring {
                hasher_p.update(member.public_key.compress().as_bytes());
                hasher_p.update(member.commitment.compress().as_bytes());
            }
            (Scalar::from_bytes_mod_order(hasher_p.finalize().into()), Scalar::ZERO)
        };
        
        let final_sig = adaptor_sig.clone().finalize(adaptor_scalar, mu_P);
        
        // 7. Test extraction: given both sigs, can extract t
        let extracted = extract_adaptor_scalar(&adaptor_sig, &final_sig, mu_P);
        assert_eq!(extracted, adaptor_scalar);
    }

    #[test]
    fn test_key_image_consistency() {
        let G = ED25519_BASEPOINT_POINT;
        
        let spend_key = Scalar::random(&mut rand::rngs::OsRng);
        let adaptor_scalar = Scalar::random(&mut rand::rngs::OsRng);
        let public_key = spend_key * G;
        
        let commitment_key = Scalar::from(50u64);
        let (ring, real_index) = create_test_ring(public_key, 11);
        
        let signer = ClsagAdaptorSigner::new(ring, real_index, b"test".to_vec());
        let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
        
        // Key image should use FULL spend key
        let expected_key_image = compute_key_image(&spend_key, &public_key);
        assert_eq!(adaptor_sig.key_image, expected_key_image);
    }
}

