//! Comprehensive tests for standard CLSAG implementation
//! 
//! These tests verify CLSAG signing and verification correctness,
//! which is the foundation for adaptor signatures.

use curve25519_dalek::{
    constants::ED25519_BASEPOINT_POINT,
    edwards::EdwardsPoint,
    scalar::Scalar,
};
use xmr_secret_gen::clsag::{
    RingMember, ClsagSigner, verify_clsag, ClsagSignature,
};
use rand::rngs::OsRng;

fn create_test_ring(real_public_key: EdwardsPoint, real_commitment: EdwardsPoint, size: usize) -> (Vec<RingMember>, usize) {
    let mut ring = Vec::new();
    let real_index = size / 2; // Put real key in the middle
    
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

#[test]
fn test_clsag_sign_and_verify() {
    // Basic sign and verify test
    let g = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * g;
    let commitment_key = Scalar::random(&mut OsRng);
    let commitment = commitment_key * g;
    
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    let message = b"test transaction".to_vec();
    
    let signer = ClsagSigner::new(ring.clone(), real_index, message.clone());
    let signature = signer.sign(spend_key, commitment_key);
    
    // Verify the signature
    let is_valid = verify_clsag(&ring, &message, &signature);
    assert!(is_valid, "Valid CLSAG signature must verify");
}

#[test]
fn test_clsag_different_messages() {
    // Same ring, different messages must produce different signatures
    let g = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * g;
    let commitment_key = Scalar::random(&mut OsRng);
    let commitment = commitment_key * g;
    
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let message1 = b"transaction 1".to_vec();
    let message2 = b"transaction 2".to_vec();
    
    let signer1 = ClsagSigner::new(ring.clone(), real_index, message1.clone());
    let signer2 = ClsagSigner::new(ring.clone(), real_index, message2.clone());
    
    let sig1 = signer1.sign(spend_key, commitment_key);
    let sig2 = signer2.sign(spend_key, commitment_key);
    
    // Signatures should be different
    assert_ne!(sig1.c1, sig2.c1, "Different messages must produce different c1");
    assert_ne!(sig1.responses, sig2.responses, "Different messages must produce different responses");
    
    // Both should verify
    assert!(verify_clsag(&ring, &message1, &sig1), "Signature 1 must verify");
    assert!(verify_clsag(&ring, &message2, &sig2), "Signature 2 must verify");
    
    // Cross-verification should fail
    assert!(!verify_clsag(&ring, &message1, &sig2), "Signature 2 must not verify message 1");
    assert!(!verify_clsag(&ring, &message2, &sig1), "Signature 1 must not verify message 2");
}

#[test]
fn test_clsag_different_rings() {
    // Same message, different rings must produce different signatures
    let g = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * g;
    let commitment_key = Scalar::random(&mut OsRng);
    let commitment = commitment_key * g;
    
    let (ring1, real_index1) = create_test_ring(public_key, commitment, 11);
    let (ring2, real_index2) = create_test_ring(public_key, commitment, 11);
    
    let message = b"same message".to_vec();
    
    let signer1 = ClsagSigner::new(ring1.clone(), real_index1, message.clone());
    let signer2 = ClsagSigner::new(ring2.clone(), real_index2, message.clone());
    
    let sig1 = signer1.sign(spend_key, commitment_key);
    let sig2 = signer2.sign(spend_key, commitment_key);
    
    // Signatures should be different (different decoys)
    assert_ne!(sig1.c1, sig2.c1, "Different rings must produce different c1");
    
    // Each should verify with its own ring
    assert!(verify_clsag(&ring1, &message, &sig1), "Signature 1 must verify with ring 1");
    assert!(verify_clsag(&ring2, &message, &sig2), "Signature 2 must verify with ring 2");
}

#[test]
fn test_clsag_ring_sizes() {
    // Test with different ring sizes
    let g = ED25519_BASEPOINT_POINT;
    
    for ring_size in [5, 11, 25, 50] {
        let spend_key = Scalar::random(&mut OsRng);
        let public_key = spend_key * g;
        let commitment_key = Scalar::random(&mut OsRng);
        let commitment = commitment_key * g;
        
        let (ring, real_index) = create_test_ring(public_key, commitment, ring_size);
        let message = format!("ring size {}", ring_size).into_bytes();
        
        let signer = ClsagSigner::new(ring.clone(), real_index, message.clone());
        let signature = signer.sign(spend_key, commitment_key);
        
        assert!(verify_clsag(&ring, &message, &signature), 
                "CLSAG must work with ring size {}", ring_size);
    }
}

#[test]
fn test_clsag_key_image_consistency() {
    // Key image must be consistent across multiple signatures
    let g = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * g;
    let commitment_key = Scalar::random(&mut OsRng);
    let commitment = commitment_key * g;
    
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let mut key_images = Vec::new();
    
    for i in 0..5 {
        let message = format!("message {}", i).into_bytes();
        let signer = ClsagSigner::new(ring.clone(), real_index, message);
        let signature = signer.sign(spend_key, commitment_key);
        
        key_images.push(signature.key_image);
    }
    
    // All key images must be identical
    for i in 1..key_images.len() {
        assert_eq!(key_images[0], key_images[i], 
                  "Key image must be consistent across signatures");
    }
}

#[test]
fn test_clsag_invalid_signature_rejected() {
    // Tampered signatures must be rejected
    let g = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * g;
    let commitment_key = Scalar::random(&mut OsRng);
    let commitment = commitment_key * g;
    
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    let message = b"test transaction".to_vec();
    
    let signer = ClsagSigner::new(ring.clone(), real_index, message.clone());
    let mut signature = signer.sign(spend_key, commitment_key);
    
    // Tamper with c1
    signature.c1 = signature.c1 + Scalar::from(1u64);
    assert!(!verify_clsag(&ring, &message, &signature), 
           "Tampered c1 must be rejected");
    
    // Restore and tamper with responses
    let mut signature = signer.sign(spend_key, commitment_key);
    signature.responses[0] = signature.responses[0] + Scalar::from(1u64);
    assert!(!verify_clsag(&ring, &message, &signature), 
           "Tampered response must be rejected");
}

#[test]
fn test_clsag_wrong_message_rejected() {
    // Signature for one message must not verify for another
    let g = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * g;
    let commitment_key = Scalar::random(&mut OsRng);
    let commitment = commitment_key * g;
    
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let message1 = b"message 1".to_vec();
    let message2 = b"message 2".to_vec();
    
    let signer = ClsagSigner::new(ring.clone(), real_index, message1.clone());
    let signature = signer.sign(spend_key, commitment_key);
    
    assert!(verify_clsag(&ring, &message1, &signature), 
           "Signature must verify for correct message");
    assert!(!verify_clsag(&ring, &message2, &signature), 
           "Signature must not verify for wrong message");
}

#[test]
fn test_clsag_wrong_ring_rejected() {
    // Signature for one ring must not verify for another
    let g = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * g;
    let commitment_key = Scalar::random(&mut OsRng);
    let commitment = commitment_key * g;
    
    let (ring1, real_index1) = create_test_ring(public_key, commitment, 11);
    let (ring2, _real_index2) = create_test_ring(public_key, commitment, 11);
    
    let message = b"test message".to_vec();
    
    let signer = ClsagSigner::new(ring1.clone(), real_index1, message.clone());
    let signature = signer.sign(spend_key, commitment_key);
    
    assert!(verify_clsag(&ring1, &message, &signature), 
           "Signature must verify for correct ring");
    assert!(!verify_clsag(&ring2, &message, &signature), 
           "Signature must not verify for wrong ring");
}

#[test]
fn test_clsag_ring_closure() {
    // The ring must close: final challenge must equal c1
    let g = ED25519_BASEPOINT_POINT;
    
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * g;
    let commitment_key = Scalar::random(&mut OsRng);
    let commitment = commitment_key * g;
    
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    let message = b"test transaction".to_vec();
    
    let signer = ClsagSigner::new(ring.clone(), real_index, message.clone());
    let signature = signer.sign(spend_key, commitment_key);
    
    // Verification checks ring closure internally
    assert!(verify_clsag(&ring, &message, &signature), 
           "Ring closure must be correct");
}

