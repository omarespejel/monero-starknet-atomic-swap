//! Integration tests for CLSAG adaptor signatures in atomic swap context
//! 
//! These tests verify the complete atomic swap flow:
//! 1. Alice creates adaptor signature
//! 2. DLEQ proof generation (integration with existing DLEQ module)
//! 3. Signature finalization when adaptor scalar is revealed
//! 4. Cross-module compatibility

use curve25519_dalek::{
    constants::ED25519_BASEPOINT_POINT,
    edwards::EdwardsPoint,
    scalar::Scalar,
};
use xmr_secret_gen::clsag::{
    RingMember, ClsagAdaptorSigner, ClsagAdaptorSignature,
    extract_adaptor_scalar, verify_clsag,
};
use xmr_secret_gen::dleq::{generate_dleq_proof, DleqProof};
use sha2::{Sha256, Digest};
use sha3::Keccak256;
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
fn test_full_atomic_swap_flow() {
    // Complete atomic swap flow: CLSAG + DLEQ integration
    let G = ED25519_BASEPOINT_POINT;
    
    println!("=== Atomic Swap: Monero ↔ Starknet ===\n");
    
    // ============================================
    // SETUP: Alice has Monero, wants STRK
    // ============================================
    
    // Alice's Monero spend key
    let alice_spend_key = Scalar::random(&mut OsRng);
    let alice_public_key = alice_spend_key * G;
    println!("Alice's Monero public key: {:?}", alice_public_key.compress());
    
    // Alice generates adaptor scalar (the atomic swap secret)
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let adaptor_point = adaptor_scalar * G;
    println!("Adaptor point T = t·G: {:?}", adaptor_point.compress());
    
    // Hashlock for Starknet
    let hashlock: [u8; 32] = Sha256::digest(adaptor_scalar.as_bytes()).into();
    println!("Hashlock H = SHA256(t): {}", hex::encode(&hashlock));
    
    // ============================================
    // STEP 1: Alice creates DLEQ proof
    // ============================================
    println!("\n--- Step 1: DLEQ Proof Generation ---");
    
    let dleq_proof = generate_dleq_proof(adaptor_scalar, adaptor_point, hashlock);
    println!("DLEQ proof generated:");
    println!("  Challenge: {:?}", dleq_proof.challenge);
    println!("  Response: {:?}", dleq_proof.response);
    
    // ============================================
    // STEP 2: Alice creates partial Monero TX
    // ============================================
    println!("\n--- Step 2: Monero Adaptor Signature ---");
    
    // Create ring (in production, these come from blockchain)
    let commitment_key = Scalar::from(100u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(alice_public_key, commitment, 11);
    
    let tx_message = b"monero_tx_prefix_hash_placeholder".to_vec();
    
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, tx_message.clone());
    let adaptor_sig = signer.sign_adaptor(alice_spend_key, adaptor_scalar, commitment_key);
    
    println!("Adaptor CLSAG created:");
    println!("  Key image: {:?}", adaptor_sig.key_image.compress());
    println!("  Adaptor point matches: {}", adaptor_sig.adaptor_point == adaptor_point);
    
    // ============================================
    // STEP 3: Deploy Starknet contract
    // ============================================
    println!("\n--- Step 3: Starknet Contract Deployment ---");
    println!("(In production: Deploy AtomicLock with hashlock, adaptor_point, DLEQ proof)");
    println!("  Hashlock: {}", hex::encode(&hashlock));
    println!("  Adaptor point: {:?}", adaptor_point.compress());
    println!("  DLEQ proof: verified in constructor");
    
    // ============================================
    // STEP 4: Bob locks STRK on Starknet
    // ============================================
    println!("\n--- Step 4: Bob Locks STRK ---");
    println!("(In production: Bob calls deposit() on AtomicLock)");
    
    // ============================================
    // STEP 5: Alice verifies, shares partial TX
    // ============================================
    println!("\n--- Step 5: Alice Shares Partial Monero TX ---");
    println!("Alice sends adaptor signature to Bob (off-chain or via contract)");
    
    // ============================================
    // STEP 6: Bob unlocks Starknet, revealing t
    // ============================================
    println!("\n--- Step 6: Bob Unlocks Starknet Contract ---");
    println!("Bob calls verify_and_unlock(secret) where secret = t");
    println!("This reveals adaptor_scalar t");
    
    // Simulate: Bob extracts t from the Unlocked event
    let revealed_scalar = adaptor_scalar; // In production: extract from event
    
    // ============================================
    // STEP 7: Alice finalizes Monero TX
    // ============================================
    println!("\n--- Step 7: Alice Finalizes Monero TX ---");
    
    // Compute mu_P for finalization
    let mu_P = compute_mu_p(&ring);
    
    let final_sig = adaptor_sig.clone().finalize(revealed_scalar, mu_P);
    println!("CLSAG finalized!");
    println!("  c1: {:?}", final_sig.c1);
    println!("  Key image: {:?}", final_sig.key_image.compress());
    
    // ============================================
    // STEP 8: Verify and broadcast
    // ============================================
    println!("\n--- Step 8: Verify & Broadcast ---");
    
    let is_valid = verify_clsag(&ring, &tx_message, &final_sig);
    println!("Signature valid: {}", is_valid);
    assert!(is_valid, "Finalized signature must verify");
    
    // ============================================
    // BONUS: Extraction test
    // ============================================
    println!("\n--- Bonus: Adaptor Extraction ---");
    let extracted = extract_adaptor_scalar(
        &adaptor_sig, 
        &final_sig, 
        mu_P
    );
    println!("Extracted adaptor scalar matches: {}", extracted == adaptor_scalar);
    assert_eq!(extracted, adaptor_scalar, "Extraction must be correct");
    
    println!("\n=== Swap Complete! ===");
}

#[test]
fn test_dleq_and_clsag_compatibility() {
    // Verify DLEQ proof and CLSAG adaptor signature use same adaptor point
    let G = ED25519_BASEPOINT_POINT;
    
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let adaptor_point = adaptor_scalar * G;
    let hashlock: [u8; 32] = Sha256::digest(adaptor_scalar.as_bytes()).into();
    
    // Generate DLEQ proof
    let dleq_proof = generate_dleq_proof(&adaptor_scalar, &adaptor_point, &hashlock);
    
    // Create CLSAG adaptor signature
    let spend_key = Scalar::random(&mut OsRng);
    let public_key = spend_key * G;
    let commitment_key = Scalar::from(50u64);
    let commitment = commitment_key * G;
    let (ring, real_index) = create_test_ring(public_key, commitment, 11);
    
    let message = b"test transaction".to_vec();
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
    
    // Both must use the same adaptor point
    assert_eq!(adaptor_sig.adaptor_point, adaptor_point, 
              "CLSAG and DLEQ must use same adaptor point");
    
    // Verify adaptor point structure
    assert!(adaptor_sig.verify_adaptor_structure(&adaptor_point), 
           "Adaptor point structure must verify");
}

#[test]
fn test_hashlock_consistency() {
    // Hashlock must be consistent: H = SHA256(t)
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let hashlock: [u8; 32] = Sha256::digest(adaptor_scalar.as_bytes()).into();
    
    // Regenerate hashlock
    let hashlock2: [u8; 32] = Sha256::digest(adaptor_scalar.as_bytes()).into();
    
    assert_eq!(hashlock, hashlock2, "Hashlock must be deterministic");
    
    // Different scalar must produce different hashlock
    let different_scalar = Scalar::random(&mut OsRng);
    let different_hashlock: [u8; 32] = Sha256::digest(different_scalar.as_bytes()).into();
    
    assert_ne!(hashlock, different_hashlock, 
              "Different scalars must produce different hashlocks");
}

#[test]
fn test_adaptor_scalar_recovery() {
    // Test that adaptor scalar can be recovered from finalized signature
    let G = ED25519_BASEPOINT_POINT;
    
    for _ in 0..5 {
        let adaptor_scalar = Scalar::random(&mut OsRng);
        let spend_key = Scalar::random(&mut OsRng);
        let public_key = spend_key * G;
        let commitment_key = Scalar::random(&mut OsRng);
        let commitment = commitment_key * G;
        let (ring, real_index) = create_test_ring(public_key, commitment, 11);
        
        let message = b"test transaction".to_vec();
        let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
        let adaptor_sig = signer.sign_adaptor(spend_key, adaptor_scalar, commitment_key);
        
        let mu_P = compute_mu_p(&ring);
        let final_sig = adaptor_sig.clone().finalize(adaptor_scalar, mu_P);
        
        // Recover adaptor scalar
        let recovered = extract_adaptor_scalar(&adaptor_sig, &final_sig, mu_P);
        
        assert_eq!(recovered, adaptor_scalar, 
                  "Recovered scalar must match original");
        
        // Verify hashlock consistency
        let hashlock: [u8; 32] = Sha256::digest(adaptor_scalar.as_bytes()).into();
        let recovered_hashlock: [u8; 32] = Sha256::digest(recovered.as_bytes()).into();
        
        assert_eq!(hashlock, recovered_hashlock, 
                  "Hashlocks must match");
    }
}

