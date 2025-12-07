//! End-to-end atomic swap flow test
//! 
//! Simulates the full protocol without actual blockchain interaction

use xmr_secret_gen::clsag::{RingMember, ClsagAdaptorSigner, verify_clsag, extract_adaptor_scalar};
use xmr_secret_gen::dleq::generate_dleq_proof;
use curve25519_dalek::{constants::ED25519_BASEPOINT_POINT, scalar::Scalar};
use sha2::{Digest, Sha256};
use sha3::{Digest as Sha3Digest, Keccak256};
use rand::rngs::OsRng;

fn create_test_ring(real_pk: curve25519_dalek::edwards::EdwardsPoint, size: usize) -> (Vec<RingMember>, usize) {
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
fn test_full_atomic_swap_flow() {
    // === SETUP ===
    // Alice has XMR, wants STRK
    // Bob has STRK, wants XMR
    
    // 1. Alice generates her Monero spend key
    let alice_spend_key = Scalar::random(&mut OsRng);
    let alice_public_key = alice_spend_key * ED25519_BASEPOINT_POINT;
    
    // 2. Alice splits key: spend_key = base_key + adaptor_scalar
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let base_key = alice_spend_key - adaptor_scalar;
    let adaptor_point = adaptor_scalar * ED25519_BASEPOINT_POINT; // T = t*G
    
    // Verify base_key + adaptor_scalar = spend_key
    assert_eq!(base_key + adaptor_scalar, alice_spend_key,
        "Key splitting must be correct");
    
    // 3. Alice computes hashlock H = SHA-256(t)
    let hashlock: [u8; 32] = Sha256::digest(adaptor_scalar.as_bytes()).into();
    
    // 4. Alice generates DLEQ proof: proves T = t*G without revealing t
    let dleq_proof = generate_dleq_proof(&adaptor_scalar, &adaptor_point, &hashlock);
    
    // 5. Alice creates CLSAG adaptor signature for Monero TX
    let commitment_key = Scalar::from(50u64);
    let (ring, real_index) = create_test_ring(alice_public_key, 11);
    let monero_tx_message = b"monero transfer to bob".to_vec();
    
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, monero_tx_message.clone());
    let adaptor_sig = signer.sign_adaptor(alice_spend_key, adaptor_scalar, commitment_key);
    
    // === STARKNET DEPLOYMENT (simulated) ===
    // Alice deploys AtomicLock with:
    // - hashlock (8 u32 words)
    // - adaptor_point T
    // - DLEQ proof
    // - timelock
    // Contract verifies DLEQ proof in constructor
    
    // Verify adaptor point matches
    assert_eq!(adaptor_sig.adaptor_point, adaptor_point,
        "CLSAG adaptor point must match DLEQ adaptor point");
    
    // === BOB UNLOCKS STARKNET ===
    // Bob sees the adaptor signature, verifies it's valid (partial)
    // Bob decides to proceed, calls verify_and_unlock(secret)
    // For this, Bob needs the secret t (which he gets from Alice in a real swap
    // after Alice locks XMR with the adaptor sig)
    
    // In a real atomic swap:
    // - Alice broadcasts adaptor sig (partial) to Monero mempool (doesn't confirm)
    // - Bob sees it, extracts adaptor_point, verifies against Starknet contract
    // - Bob unlocks Starknet by providing t (he got t from Alice off-chain,
    //   or Alice revealed it by completing the Monero tx)
    
    // Simulating: Bob reveals t on Starknet
    let revealed_secret = adaptor_scalar; // This is what verify_and_unlock receives
    
    // === ALICE FINALIZES MONERO TX ===
    // Alice sees t revealed on Starknet, uses it to complete her signature
    let mut hasher = Keccak256::new();
    hasher.update(b"CLSAG_agg_0");
    for member in &ring {
        hasher.update(member.public_key.compress().as_bytes());
        hasher.update(member.commitment.compress().as_bytes());
    }
    let mu_p = Scalar::from_bytes_mod_order(hasher.finalize().into());
    
    let final_sig = adaptor_sig.clone().finalize(revealed_secret, mu_p);
    
    // === VERIFICATION ===
    // 1. Final Monero signature is valid
    assert!(verify_clsag(&ring, &monero_tx_message, &final_sig),
        "Alice's finalized CLSAG must be valid");
    
    // 2. Bob can extract t from observing both signatures (if needed)
    let extracted_t = extract_adaptor_scalar(&adaptor_sig, &final_sig, mu_p);
    assert_eq!(extracted_t, adaptor_scalar,
        "Extracted scalar must match original");
    
    // 3. Verify hashlock matches
    let computed_hashlock: [u8; 32] = Sha256::digest(revealed_secret.as_bytes()).into();
    assert_eq!(computed_hashlock, hashlock,
        "SHA-256(revealed_t) must match original hashlock");
    
    println!("✓ Full atomic swap flow completed successfully!");
}

#[test]
fn test_atomic_swap_with_wrong_secret_fails() {
    // Test that using wrong secret in finalization produces invalid signature
    let alice_spend_key = Scalar::random(&mut OsRng);
    let alice_public_key = alice_spend_key * ED25519_BASEPOINT_POINT;
    let adaptor_scalar = Scalar::random(&mut OsRng);
    let wrong_scalar = Scalar::random(&mut OsRng);
    let adaptor_point = adaptor_scalar * ED25519_BASEPOINT_POINT;
    
    let hashlock: [u8; 32] = Sha256::digest(adaptor_scalar.as_bytes()).into();
    let commitment_key = Scalar::from(50u64);
    let (ring, real_index) = create_test_ring(alice_public_key, 11);
    let message = b"test".to_vec();
    
    let signer = ClsagAdaptorSigner::new(ring.clone(), real_index, message.clone());
    let adaptor_sig = signer.sign_adaptor(alice_spend_key, adaptor_scalar, commitment_key);
    
    // Compute mu_p
    let mut hasher = Keccak256::new();
    hasher.update(b"CLSAG_agg_0");
    for member in &ring {
        hasher.update(member.public_key.compress().as_bytes());
        hasher.update(member.commitment.compress().as_bytes());
    }
    let mu_p = Scalar::from_bytes_mod_order(hasher.finalize().into());
    
    // Finalize with WRONG secret
    let bad_sig = adaptor_sig.finalize(wrong_scalar, mu_p);
    
    // Should NOT verify
    assert!(!verify_clsag(&ring, &message, &bad_sig),
        "Wrong secret must produce invalid signature");
}

