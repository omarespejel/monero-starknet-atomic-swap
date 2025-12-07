//! Tests that CLSAG adaptor scalar matches DLEQ proof scalar
//! 
//! This is the critical bridge between Monero and Starknet

use xmr_secret_gen::clsag::{self, RingMember, ClsagAdaptorSigner, verify_clsag, extract_adaptor_scalar};
use xmr_secret_gen::dleq::generate_dleq_proof;
use curve25519_dalek::{constants::ED25519_BASEPOINT_POINT, edwards::EdwardsPoint, scalar::Scalar};
use sha2::{Digest, Sha256};
use sha3::{Digest as Sha3Digest, Keccak256};
use rand::rngs::OsRng;

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
fn test_same_scalar_for_dleq_and_clsag() {
    // This is THE critical test - same t for both protocols
    
    // 1. Generate the adaptor scalar (this goes to both DLEQ and CLSAG)
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let adaptor_point = adaptor_scalar * ED25519_BASEPOINT_POINT;
    
    // 2. Generate hashlock H = SHA-256(t) for Starknet
    let hashlock: [u8; 32] = Sha256::digest(adaptor_scalar.as_bytes()).into();
    
    // 3. Generate DLEQ proof (for Starknet)
    let dleq_proof = generate_dleq_proof(&adaptor_scalar, &adaptor_point, &hashlock);
    
    // 4. Verify DLEQ proof has correct adaptor point
    let cairo_format = dleq_proof.to_cairo_format(&adaptor_point);
    assert_eq!(
        &cairo_format.adaptor_point_compressed,
        adaptor_point.compress().as_bytes(),
        "DLEQ adaptor point must match"
    );
    
    // 5. Create CLSAG adaptor signature with SAME scalar
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * ED25519_BASEPOINT_POINT;
    let commitment_key = Scalar::from(50u64);
    
    let (ring, real_index) = create_test_ring(public_key, 11);
    let message = b"monero tx".to_vec();
    
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    // 6. CRITICAL: CLSAG adaptor point must match DLEQ adaptor point
    assert_eq!(
        adaptor_sig.adaptor_point.compress().as_bytes(),
        adaptor_point.compress().as_bytes(),
        "CLSAG and DLEQ must use same adaptor point T = t*G"
    );
    
    // 7. When t is revealed on Starknet, it finalizes CLSAG
    let mut hasher = Keccak256::new();
    hasher.update(b"CLSAG_agg_0");
    for member in &ring {
        hasher.update(member.public_key.compress().as_bytes());
        hasher.update(member.commitment.compress().as_bytes());
    }
    let mu_p = Scalar::from_bytes_mod_order(hasher.finalize().into());
    
    let final_sig = adaptor_sig.clone().finalize(adaptor_scalar, mu_p);
    assert!(verify_clsag(&ring, &message, &final_sig),
        "Finalized signature must verify");
}

#[test]
fn test_hashlock_matches_adaptor_scalar() {
    // Verify SHA-256(t) produces correct hashlock for Cairo
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let hashlock: [u8; 32] = Sha256::digest(adaptor_scalar.as_bytes()).into();
    
    // Convert to 8 u32 words (big-endian, Cairo format)
    let hash_words: [u32; 8] = std::array::from_fn(|i| {
        u32::from_be_bytes([
            hashlock[i * 4],
            hashlock[i * 4 + 1],
            hashlock[i * 4 + 2],
            hashlock[i * 4 + 3],
        ])
    });
    
    // Reconstruct and verify
    let mut reconstructed = [0u8; 32];
    for (i, word) in hash_words.iter().enumerate() {
        reconstructed[i * 4..i * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    assert_eq!(hashlock, reconstructed, "Hashlock reconstruction must match");
}

#[test]
fn test_dleq_clsag_scalar_consistency() {
    // Multiple runs with different scalars - all must be consistent
    for _ in 0..5 {
        let adaptor_scalar = Scalar::random(&mut OsRng);
        let adaptor_point = adaptor_scalar * ED25519_BASEPOINT_POINT;
        let hashlock: [u8; 32] = Sha256::digest(adaptor_scalar.as_bytes()).into();
        
        // DLEQ proof
        let dleq_proof = generate_dleq_proof(&adaptor_scalar, &adaptor_point, &hashlock);
        
        // CLSAG adaptor signature
        let spend_key = Scalar::random(&mut OsRng);
        let public_key = spend_key * ED25519_BASEPOINT_POINT;
        let commitment_key = Scalar::from(50u64);
        let (ring, real_index) = create_test_ring(public_key, 11);
        let message = b"test".to_vec();
        
        let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
        let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
        
        // Both must use same adaptor point
        assert_eq!(
            adaptor_sig.adaptor_point.compress().as_bytes(),
            adaptor_point.compress().as_bytes(),
            "Adaptor points must match"
        );
        
        // Verify DLEQ adaptor point matches
        let cairo_format = dleq_proof.to_cairo_format(&adaptor_point);
        assert_eq!(
            &cairo_format.adaptor_point_compressed,
            adaptor_point.compress().as_bytes(),
            "DLEQ adaptor point must match"
        );
    }
}

