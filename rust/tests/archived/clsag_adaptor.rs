//! Comprehensive tests for CLSAG adaptor signatures
//! 
//! These tests verify the adaptor signature flow critical for atomic swaps:
//! 1. Partial signature creation
//! 2. Finalization when adaptor scalar is revealed
//! 3. Extraction of adaptor scalar from signatures

use curve25519_dalek::{
    constants::ED25519_BASEPOINT_POINT,
    edwards::EdwardsPoint,
    scalar::Scalar,
};
use xmr_secret_gen::clsag::{
    RingMember, ClsagAdaptorSigner,
    extract_adaptor_scalar, verify_clsag,
};
use sha3::{Digest, Keccak256};
use rand::rngs::OsRng;

fn create_test_ring(real_public_key: EdwardsPoint, real_commitment: EdwardsPoint, size: usize) -> (Vec<RingMember>, usize) {
    let mut ring = Vec::new();
    let real_index = size / 2;
    
    for i in 0..size {
        let (pk, commitment) = if i == real_index {
            (real_public_key, real_commitment)
        } else {
            let fake_key = Scalar::random(&mut OsRng) * ED25519_BASEPOINT_POINT;
            let fake_commitment = Scalar::random(&mut OsRng) * ED25519_BASEPOINT_POINT;
            (fake_key, fake_commitment)
        };
        
        ring.push(RingMember {
            public_key: pk,
            commitment,
        });
    }
    
    (ring, real_index)
}

fn compute_mu_p(ring: &[RingMember]) -> Scalar {
    let mut hasher = Keccak256::new();
    hasher.update(b"CLSAG_agg_0");
    for member in ring {
        hasher.update(member.public_key.compress().as_bytes());
        hasher.update(member.commitment.compress().as_bytes());
    }
    Scalar::from_bytes_mod_order(hasher.finalize().into())
}

#[test]
fn test_adaptor_signature_flow() {
    // Full adaptor signature flow: create partial, finalize, extract
    let G = ED25519_BASEPOINT_POINT;
    
    // 1. Alice has a full spend key
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * G;
    
    // 2. She generates adaptor scalar (the atomic swap secret)
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let adaptor_point = adaptor_scalar * G;
    
    // 3. Create ring
    let commitment_key = Scalar::from(50u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    // 4. Create adaptor signature
    let message = b"test transaction".to_vec();
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    // 5. Verify adaptor point matches
    assert_eq!(adaptor_sig.adaptor_point, adaptor_point, 
              "Adaptor point must match");
    
    // 6. Finalize when t is revealed
    let mu_P = compute_mu_p(&ring);
    let final_sig = adaptor_sig.clone().finalize(adaptor_scalar, mu_P);
    
    // 7. Verify the finalized signature
    let is_valid = verify_clsag(&ring, &message, &final_sig);
    assert!(is_valid, "Finalized signature must verify");
    
    // 8. Test extraction: given both sigs, can extract t
    let extracted = extract_adaptor_scalar(&adaptor_sig, &final_sig, mu_P);
    assert_eq!(extracted, adaptor_scalar, 
              "Extracted adaptor scalar must match original");
}

#[test]
fn test_key_image_consistency() {
    // Key image must use FULL spend key, not partial
    let G = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let public_key = spend_key * G;
    
    let commitment_key = Scalar::from(50u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let signer = ClsagAdaptorSigner::new(ring, real_index, b"test".to_vec());
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    // Key image should use FULL spend key
    use xmr_secret_gen::clsag::compute_key_image;
    let expected_key_image = compute_key_image(&spend_key, &public_key);
    assert_eq!(adaptor_sig.key_image, expected_key_image, 
              "Key image must use full spend key");
}

#[test]
fn test_adaptor_point_correctness() {
    // Adaptor point must be t·G
    let G = ED25519_BASEPOINT_POINT;
    
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let expected_adaptor_point = adaptor_scalar * G;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * G;
    let commitment_key = Scalar::from(50u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let signer = ClsagAdaptorSigner::new(ring, real_index, b"test".to_vec());
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    assert_eq!(adaptor_sig.adaptor_point, expected_adaptor_point, 
              "Adaptor point must be t·G");
}

#[test]
fn test_partial_signature_cannot_verify() {
    // Partial (adaptor) signature must NOT verify as full CLSAG
    let G = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * G;
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let commitment_key = Scalar::from(50u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let message = b"test transaction".to_vec();
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    // Try to verify partial signature as full CLSAG (should fail)
    // Note: We need to convert adaptor sig to standard sig format
    use xmr_secret_gen::clsag::ClsagSignature;
    let partial_as_standard = ClsagSignature {
        c1: adaptor_sig.c1,
        responses: adaptor_sig.responses.clone(),
        key_image: adaptor_sig.key_image,
        commitment_key_image: adaptor_sig.commitment_key_image,
    };
    
    // Partial signature should NOT verify
    assert!(!verify_clsag(&ring, &message, &partial_as_standard), 
           "Partial signature must not verify as full CLSAG");
}

#[test]
fn test_finalization_produces_valid_signature() {
    // Finalized signature must verify
    let G = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * G;
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let commitment_key = Scalar::from(50u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let message = b"test transaction".to_vec();
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    let mu_P = compute_mu_p(&ring);
    let final_sig = adaptor_sig.finalize(adaptor_scalar, mu_P);
    
    assert!(verify_clsag(&ring, &message, &final_sig), 
           "Finalized signature must verify");
}

#[test]
fn test_extraction_correctness() {
    // Extraction must recover the exact adaptor scalar
    let G = ED25519_BASEPOINT_POINT;
    
    for _ in 0..10 {
        let spend_key = Scalar::random(&mut OsRng);
        let public_key = spend_key * G;
        let adaptor_scalar = Scalar::random(&mut OsRng);
        let commitment_key = Scalar::random(&mut OsRng);
        let commitment = commitment_key * G;
        let (ring, real_index) = create_test_ring(public_key, commitment, 11);
        
        let message = b"test transaction".to_vec();
        let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
        let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
        
        let mu_P = compute_mu_p(&ring);
        let final_sig = adaptor_sig.clone().finalize(adaptor_scalar, mu_P);
        
        let extracted = extract_adaptor_scalar(&adaptor_sig, &final_sig, mu_P);
        
        assert_eq!(extracted, adaptor_scalar, 
                  "Extracted scalar must match original");
    }
}

#[test]
fn test_different_adaptor_scalars() {
    // Different adaptor scalars must produce different partial signatures
    let G = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * G;
    let commitment_key = Scalar::from(50u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let message = b"test transaction".to_vec();
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    
    let adaptor_scalar1 = Scalar::random(&mut OsRng);
    let adaptor_scalar2 = Scalar::random(&mut OsRng);
    
    let sig1 = signer.sign_adaptor(spend_key, adaptor_scalar1, commitment_key);
    let sig2 = signer.sign_adaptor(spend_key, adaptor_scalar2, commitment_key);
    
    // Adaptor points must be different
    assert_ne!(sig1.adaptor_point, sig2.adaptor_point, 
              "Different adaptor scalars must produce different adaptor points");
    
    // Responses at real_index must be different
    assert_ne!(sig1.responses[real_index], sig2.responses[real_index], 
              "Different adaptor scalars must produce different responses");
}

#[test]
fn test_finalization_with_wrong_scalar_fails() {
    // Finalizing with wrong adaptor scalar must produce invalid signature
    let G = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * G;
    let correct_adaptor_scalar = Scalar::random(&mut OsRng);
    let wrong_adaptor_scalar = Scalar::random(&mut OsRng);
    let commitment_key = Scalar::from(50u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let message = b"test transaction".to_vec();
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    let adaptor_sig = signer.sign_adaptor(spend_key, correct_adaptor_scalar, commitment_key);
    
    let mu_P = compute_mu_p(&ring);
    
    // Finalize with WRONG scalar
    let wrong_final_sig = adaptor_sig.finalize(wrong_adaptor_scalar, mu_P);
    
    // Should NOT verify
    assert!(!verify_clsag(&ring, &message, &wrong_final_sig), 
           "Signature finalized with wrong scalar must not verify");
}

#[test]
fn test_adaptor_structure_verification() {
    // verify_adaptor_structure must check adaptor point
    let G = ED25519_BASEPOINT_POINT;
    
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let expected_adaptor_point = adaptor_scalar * G;
    let wrong_adaptor_point = Scalar::random(&mut OsRng) * G;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * G;
    let commitment_key = Scalar::from(50u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let signer = ClsagAdaptorSigner::new(ring, real_index, b"test".to_vec());
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    // Correct adaptor point
    assert!(adaptor_sig.verify_adaptor_structure(&expected_adaptor_point), 
           "Correct adaptor point must verify");
    
    // Wrong adaptor point
    assert!(!adaptor_sig.verify_adaptor_structure(&wrong_adaptor_point), 
           "Wrong adaptor point must not verify");
}

#[test]
fn test_multiple_finalizations() {
    // Multiple finalizations with same scalar must produce same signature
    let G = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * G;
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let commitment_key = Scalar::from(50u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let message = b"test transaction".to_vec();
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    let adaptor_sig1 = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    let adaptor_sig2 = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    let mu_P = compute_mu_p(&ring);
    
    let final1 = adaptor_sig1.finalize(adaptor_scalar, mu_P);
    let final2 = adaptor_sig2.finalize(adaptor_scalar, mu_P);
    
    // Both should verify
    assert!(verify_clsag(&ring, &message, &final1), "Final 1 must verify");
    assert!(verify_clsag(&ring, &message, &final2), "Final 2 must verify");
    
    // Key images must be identical
    assert_eq!(final1.key_image, final2.key_image, 
              "Key images must be identical");
}

