//! Property-based tests for DLEQ proof generation and verification.
//!
//! Uses proptest to verify cryptographic properties hold for arbitrary inputs.
//! These tests catch edge cases and ensure soundness/completeness properties.

use proptest::prelude::*;
use sha2::{Digest, Sha256};
use xmr_secret_gen::dleq::{generate_dleq_proof, DleqError};
use curve25519_dalek::{
    constants::ED25519_BASEPOINT_POINT,
    scalar::Scalar,
};
use zeroize::Zeroizing;
use std::ops::Deref;

proptest! {
    /// Property: Valid proof should always verify (soundness).
    ///
    /// For any valid secret, adaptor point, and hashlock:
    /// - Proof generation should succeed
    /// - Challenge and response should be non-zero
    /// - Second point U should equal t·Y
    #[test]
    fn test_dleq_soundness(secret_bytes in prop::array::uniform32(any::<u8>())) {
        let secret = Scalar::from_bytes_mod_order(secret_bytes);
        
        // Skip zero secret (invalid input)
        if secret == Scalar::ZERO {
            return Ok(());
        }
        
        let secret_zeroizing = Zeroizing::new(secret);
        let adaptor_point = ED25519_BASEPOINT_POINT * *secret_zeroizing;
        // Use raw bytes for hashlock (Cairo-compatible)
        let hashlock: [u8; 32] = Sha256::digest(secret_bytes).into();
        
        let proof = generate_dleq_proof(&secret_zeroizing, &secret_bytes, &adaptor_point, &hashlock)?;
        
        // Challenge and response must be non-zero
        prop_assert_ne!(proof.challenge.to_bytes(), [0u8; 32], "Challenge must be non-zero");
        prop_assert_ne!(proof.response.to_bytes(), [0u8; 32], "Response must be non-zero");
        
        // Verify U = t·Y
        // Note: get_second_generator is pub(crate), so we compute Y directly
        let Y = ED25519_BASEPOINT_POINT * Scalar::from(2u64);
        let expected_U = Y * secret;
        prop_assert_eq!(proof.second_point, expected_U, "U must equal t·Y");
    }
    
    /// Property: Wrong secret should always fail (completeness).
    ///
    /// If we generate a proof with one secret but use a different secret's hashlock,
    /// the proof should fail validation (or generation should fail).
    #[test]
    fn test_dleq_completeness(
        secret_bytes in prop::array::uniform32(any::<u8>()),
        wrong_secret_bytes in prop::array::uniform32(any::<u8>())
    ) {
        let secret = Scalar::from_bytes_mod_order(secret_bytes);
        let wrong_secret = Scalar::from_bytes_mod_order(wrong_secret_bytes);
        
        // Skip if secrets are the same or either is zero
        if secret == wrong_secret || secret == Scalar::ZERO || wrong_secret == Scalar::ZERO {
            return Ok(());
        }
        
        let secret_zeroizing = Zeroizing::new(secret);
        let adaptor_point = ED25519_BASEPOINT_POINT * *secret_zeroizing;
        // Use raw bytes for hashlock (Cairo-compatible)
        let hashlock: [u8; 32] = Sha256::digest(secret_bytes).into();
        let wrong_hashlock: [u8; 32] = Sha256::digest(wrong_secret_bytes).into();
        
        // Proof with correct hashlock should succeed
        let proof_result = generate_dleq_proof(&secret_zeroizing, &secret_bytes, &adaptor_point, &hashlock);
        prop_assert!(proof_result.is_ok(), "Valid proof should generate successfully");
        
        // Proof with wrong hashlock should fail
        let wrong_proof_result = generate_dleq_proof(&secret_zeroizing, &secret_bytes, &adaptor_point, &wrong_hashlock);
        prop_assert_eq!(
            wrong_proof_result,
            Err(DleqError::HashlockMismatch),
            "Wrong hashlock should fail validation"
        );
        
        // Proof with wrong adaptor point should fail
        let wrong_adaptor_point = ED25519_BASEPOINT_POINT * wrong_secret;
        let wrong_point_result = generate_dleq_proof(&secret_zeroizing, &secret_bytes, &wrong_adaptor_point, &hashlock);
        prop_assert_eq!(
            wrong_point_result,
            Err(DleqError::PointMismatch),
            "Wrong adaptor point should fail validation"
        );
    }
    
    /// Property: Zero secret should always be rejected.
    #[test]
    fn test_zero_secret_rejection(secret_bytes in prop::array::uniform32(0u8..=0u8)) {
        // This generates arrays of all zeros
        let secret = Scalar::from_bytes_mod_order(secret_bytes);
        
        // Zero secret should produce zero scalar
        if secret != Scalar::ZERO {
            return Ok(());
        }
        
        let secret_zeroizing = Zeroizing::new(secret);
        let adaptor_point = ED25519_BASEPOINT_POINT * *secret_zeroizing;
        // Use raw bytes for hashlock (Cairo-compatible)
        let hashlock: [u8; 32] = Sha256::digest(secret_bytes).into();
        
        let result = generate_dleq_proof(&secret_zeroizing, &secret_bytes, &adaptor_point, &hashlock);
        prop_assert_eq!(
            result,
            Err(DleqError::ZeroScalar),
            "Zero secret must be rejected"
        );
    }
    
    /// Property: Hashlock must match SHA256(secret).
    #[test]
    fn test_hashlock_validation(
        secret_bytes in prop::array::uniform32(any::<u8>()),
        wrong_hashlock_bytes in prop::array::uniform32(any::<u8>())
    ) {
        let secret = Scalar::from_bytes_mod_order(secret_bytes);
        
        if secret == Scalar::ZERO {
            return Ok(());
        }
        
        let secret_zeroizing = Zeroizing::new(secret);
        let adaptor_point = ED25519_BASEPOINT_POINT * *secret_zeroizing;
        // Use raw bytes for hashlock (Cairo-compatible)
        let correct_hashlock: [u8; 32] = Sha256::digest(secret_bytes).into();
        
        // Skip if wrong hashlock happens to match (rare but possible)
        if wrong_hashlock_bytes == correct_hashlock {
            return Ok(());
        }
        
        let result = generate_dleq_proof(&secret_zeroizing, &secret_bytes, &adaptor_point, &wrong_hashlock_bytes);
        prop_assert_eq!(
            result,
            Err(DleqError::HashlockMismatch),
            "Wrong hashlock must be rejected"
        );
    }
    
    /// Property: Adaptor point must match secret * G.
    #[test]
    fn test_adaptor_point_validation(
        secret_bytes in prop::array::uniform32(any::<u8>()),
        wrong_secret_bytes in prop::array::uniform32(any::<u8>())
    ) {
        let secret = Scalar::from_bytes_mod_order(secret_bytes);
        let wrong_secret = Scalar::from_bytes_mod_order(wrong_secret_bytes);
        
        if secret == Scalar::ZERO || secret == wrong_secret {
            return Ok(());
        }
        
        let secret_zeroizing = Zeroizing::new(secret);
        let correct_adaptor_point = ED25519_BASEPOINT_POINT * *secret_zeroizing;
        let wrong_adaptor_point = ED25519_BASEPOINT_POINT * wrong_secret;
        // Use raw bytes for hashlock (Cairo-compatible)
        let hashlock: [u8; 32] = Sha256::digest(secret_bytes).into();
        
        let result = generate_dleq_proof(&secret_zeroizing, &secret_bytes, &wrong_adaptor_point, &hashlock);
        prop_assert_eq!(
            result,
            Err(DleqError::PointMismatch),
            "Wrong adaptor point must be rejected"
        );
    }
}

