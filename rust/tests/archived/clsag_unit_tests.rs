//! Unit tests for CLSAG components - catch bugs at the lowest level
//! 
//! These tests verify each component in isolation before integration testing.

use xmr_secret_gen::clsag::{hash_to_point, compute_key_image, RingMember, ClsagSigner, ClsagAdaptorSigner, verify_clsag};
use curve25519_dalek::{constants::ED25519_BASEPOINT_POINT, edwards::EdwardsPoint, scalar::Scalar};
use rand::rngs::OsRng;

// ============================================
// 1. HASH-TO-POINT TESTS
// ============================================

#[test]
fn test_hash_to_point_deterministic() {
    let point = ED25519_BASEPOINT_POINT;
    let hp1 = hash_to_point(&point);
    let hp2 = hash_to_point(&point);
    assert_eq!(hp1, hp2, "Hp must be deterministic");
}

#[test]
fn test_hash_to_point_different_inputs() {
    let p1 = ED25519_BASEPOINT_POINT;
    let p2 = Scalar::from(2u64) * ED25519_BASEPOINT_POINT;
    let hp1 = hash_to_point(&p1);
    let hp2 = hash_to_point(&p2);
    assert_ne!(hp1, hp2, "Different inputs must produce different Hp");
}

#[test]
fn test_key_image_consistency() {
    let secret = Scalar::from(42u64);
    let public = secret * ED25519_BASEPOINT_POINT;
    let ki1 = compute_key_image(&secret, &public);
    let ki2 = compute_key_image(&secret, &public);
    assert_eq!(ki1, ki2, "Key image must be deterministic");
}

#[test]
fn test_key_image_different_keys() {
    let s1 = Scalar::from(1u64);
    let s2 = Scalar::from(2u64);
    let p1 = s1 * ED25519_BASEPOINT_POINT;
    let p2 = s2 * ED25519_BASEPOINT_POINT;
    let ki1 = compute_key_image(&s1, &p1);
    let ki2 = compute_key_image(&s2, &p2);
    assert_ne!(ki1, ki2, "Different keys must produce different key images");
}

// ============================================
// 2. STANDARD CLSAG TESTS  
// ============================================

fn create_test_ring(real_pk: EdwardsPoint, size: usize) -> (Vec<RingMember>, usize) {
    let mut ring = Vec::new();
    let real_index = size / 2;
    for i in 0..size {
        let (pk, commitment) = if i == real_index {
            (real_pk, Scalar::from(100u64) * ED25519_BASEPOINT_POINT)
        } else {
            let fake = Scalar::random(&mut OsRng) * ED25519_BASEPOINT_POINT;
            (fake, Scalar::random(&mut OsRng) * ED25519_BASEPOINT_POINT)
        };
        ring.push(RingMember { public_key: pk, commitment });
    }
    (ring, real_index)
}

#[test]
fn test_standard_clsag_sign_verify() {
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * ED25519_BASEPOINT_POINT;
    let commitment_key = Scalar::from(50u64);
    
    let (ring, real_index) = create_test_ring(public_key, 11);
    let message = b"test transaction".to_vec();
    
    let signer = ClsagSigner::new(ring.clone(), real_index, message.clone());
    let sig = signer.sign(spend_key, commitment_key);
    
    // Verify signature
    assert!(verify_clsag(&ring, &message, &sig), "Valid signature must verify");
}

#[test]
fn test_standard_clsag_wrong_message_fails() {
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * ED25519_BASEPOINT_POINT;
    let commitment_key = Scalar::from(50u64);
    
    let (ring, real_index) = create_test_ring(public_key, 11);
    let message = b"test transaction".to_vec();
    
    let signer = ClsagSigner::new(ring.clone(), real_index, message);
    let sig = signer.sign(spend_key, commitment_key);
    
    // Wrong message should fail
    let wrong_message = b"wrong transaction".to_vec();
    assert!(!verify_clsag(&ring, &wrong_message, &sig), "Wrong message must fail");
}

#[test]
fn test_standard_clsag_ring_sizes() {
    for size in [2, 7, 11, 16] {
        let spend_key = Scalar::random(&mut OsRng);
        let public_key = spend_key * ED25519_BASEPOINT_POINT;
        let commitment_key = Scalar::from(50u64);
        
        let (ring, real_index) = create_test_ring(public_key, size);
        let message = format!("test ring size {}", size).into_bytes();
        
        let signer = ClsagSigner::new(ring.clone(), real_index, message.clone());
        let sig = signer.sign(spend_key, commitment_key);
        
        assert!(verify_clsag(&ring, &message, &sig),
            "Ring size {} should work", size);
    }
}

// ============================================
// 3. ADAPTOR CLSAG TESTS
// ============================================

#[test]
fn test_adaptor_point_matches() {
    let spend_key = Scalar::random(&mut OsRng);
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let expected_adaptor_point = adaptor_scalar * ED25519_BASEPOINT_POINT;
    let public_key = spend_key * ED25519_BASEPOINT_POINT;
    let commitment_key = Scalar::from(50u64);
    
    let (ring, real_index) = create_test_ring(public_key, 11);
    let message = b"test".to_vec();
    
    let signer = ClsagAdaptorSigner::new(ring, real_index, message);
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    assert_eq!(adaptor_sig.adaptor_point, expected_adaptor_point,
        "Adaptor point T must equal t*G");
}

#[test]
fn test_adaptor_finalization_produces_valid_sig() {
    let spend_key = Scalar::random(&mut OsRng);
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let public_key = spend_key * ED25519_BASEPOINT_POINT;
    let commitment_key = Scalar::from(50u64);
    
    let (ring, real_index) = create_test_ring(public_key, 11);
    let message = b"test atomic swap".to_vec();
    
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    // Compute muP for finalization
    use sha3::{Digest, Keccak256};
    let mut hasher = Keccak256::new();
    hasher.update(b"CLSAG_agg_0");
    for member in &ring {
        hasher.update(member.public_key.compress().as_bytes());
        hasher.update(member.commitment.compress().as_bytes());
    }
    let mu_p = Scalar::from_bytes_mod_order(hasher.finalize().into());
    
    // Finalize with revealed adaptor scalar
    let final_sig = adaptor_sig.finalize(adaptor_scalar, mu_p);
    
    // CRITICAL: Finalized signature must verify as standard CLSAG
    assert!(verify_clsag(&ring, &message, &final_sig),
        "Finalized adaptor signature must be valid CLSAG");
}

#[test]
fn test_adaptor_scalar_extraction() {
    let spend_key = Scalar::random(&mut OsRng);
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let public_key = spend_key * ED25519_BASEPOINT_POINT;
    let commitment_key = Scalar::from(50u64);
    
    let (ring, real_index) = create_test_ring(public_key, 11);
    let message = b"extraction test".to_vec();
    
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message);
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    // Compute muP
    use sha3::{Digest, Keccak256};
    let mut hasher = Keccak256::new();
    hasher.update(b"CLSAG_agg_0");
    for member in &ring {
        hasher.update(member.public_key.compress().as_bytes());
        hasher.update(member.commitment.compress().as_bytes());
    }
    let mu_p = Scalar::from_bytes_mod_order(hasher.finalize().into());
    
    let final_sig = adaptor_sig.clone().finalize(adaptor_scalar, mu_p);
    
    // CRITICAL: Extract t from seeing both signatures
    use xmr_secret_gen::clsag::extract_adaptor_scalar;
    let extracted = extract_adaptor_scalar(
        &adaptor_sig, &final_sig, mu_p
    );
    
    assert_eq!(extracted, adaptor_scalar,
        "Extracted adaptor scalar must match original");
}

#[test]
fn test_wrong_adaptor_scalar_fails() {
    let spend_key = Scalar::random(&mut OsRng);
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let wrong_scalar = Scalar::random(&mut OsRng);
    let public_key = spend_key * ED25519_BASEPOINT_POINT;
    let commitment_key = Scalar::from(50u64);
    
    let (ring, real_index) = create_test_ring(public_key, 11);
    let message = b"wrong scalar test".to_vec();
    
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    use sha3::{Digest, Keccak256};
    let mut hasher = Keccak256::new();
    hasher.update(b"CLSAG_agg_0");
    for member in &ring {
        hasher.update(member.public_key.compress().as_bytes());
        hasher.update(member.commitment.compress().as_bytes());
    }
    let mu_p = Scalar::from_bytes_mod_order(hasher.finalize().into());
    
    // Finalize with WRONG scalar
    let bad_sig = adaptor_sig.finalize(wrong_scalar, mu_p);
    
    // Should NOT verify
    assert!(!verify_clsag(&ring, &message, &bad_sig),
        "Wrong adaptor scalar must produce invalid signature");
}

