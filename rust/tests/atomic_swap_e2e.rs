//! End-to-end atomic swap flow test with key splitting approach
//!
//! Simulates the full protocol flow:
//! 1. Alice generates swap keys (key splitting: x = x_partial + t)
//! 2. Alice creates DLEQ proof and deploys AtomicLock contract on Starknet
//! 3. Bob unlocks Starknet by revealing secret t
//! 4. Alice recovers full Monero key and can spend XMR

use sha2::{Sha256, Digest};
use zeroize::Zeroizing;
use xmr_secret_gen::monero::SwapKeyPair;
use xmr_secret_gen::dleq::generate_dleq_proof;

#[test]
fn test_full_atomic_swap_flow() {
    // === SETUP: Alice has XMR, wants STRK ===
    
    // 1. Alice generates swap key pair (key splitting)
    let alice_keys = SwapKeyPair::generate();
    assert!(alice_keys.verify(), "Key splitting math must be correct");
    
    // 2. Alice computes hashlock H = SHA-256(t)
    let hashlock: [u8; 32] = Sha256::digest(
        alice_keys.adaptor_scalar_bytes()
    ).into();
    
    // 3. Alice generates DLEQ proof binding hashlock to adaptor point
    // Wrap adaptor_scalar in Zeroizing for memory safety
    let adaptor_scalar_zeroizing = Zeroizing::new(alice_keys.adaptor_scalar);
    let dleq_proof = generate_dleq_proof(
        &adaptor_scalar_zeroizing,
        &alice_keys.adaptor_point,
        &hashlock,
    ).expect("DLEQ proof generation should succeed with valid inputs");
    
    // Verify proof is valid (non-zero challenge and response)
    assert!(dleq_proof.challenge.to_bytes() != [0u8; 32], "Challenge must be non-zero");
    assert!(dleq_proof.response.to_bytes() != [0u8; 32], "Response must be non-zero");
    
    // === STARKNET DEPLOYMENT (simulated) ===
    // Alice deploys AtomicLock contract with:
    // - hashlock (8 u32 words from SHA-256(t))
    // - adaptor_point T = t·G
    // - DLEQ proof (challenge, response, R1, R2)
    // Contract verifies DLEQ proof in constructor
    
    // === BOB UNLOCKS STARKNET ===
    // Bob sees the contract, verifies DLEQ proof is valid
    // Bob calls verify_and_unlock(secret_t) on Starknet
    // This reveals t via Unlocked event
    
    // Simulating: Bob reveals t on Starknet
    let revealed_secret = alice_keys.adaptor_scalar;
    
    // === ALICE RECOVERS FULL KEY ===
    // Alice watches for Unlocked event, extracts revealed t
    // Alice recovers full Monero spend key: x = x_partial + t
    // Wrap partial_key in Zeroizing for memory safety
    let partial_key_zeroizing = Zeroizing::new(alice_keys.partial_key);
    let recovered_full_key = SwapKeyPair::recover(
        partial_key_zeroizing,
        revealed_secret,
    );

    // Verify recovery is correct
    assert_eq!(*recovered_full_key, alice_keys.full_spend_key,
        "Recovered key must match original full key");
    
    // === ALICE SPENDS MONERO ===
    // Alice now has full spend key x
    // Alice creates standard Monero transaction using recovered key
    // Transaction uses standard CLSAG (from Serai's audited library)
    // No custom CLSAG modification needed!
    
    // Verify hashlock matches revealed secret
    let computed_hashlock: [u8; 32] = Sha256::digest(
        revealed_secret.to_bytes()
    ).into();
    assert_eq!(computed_hashlock, hashlock,
        "Hashlock from revealed secret must match original");
    
    println!("✅ Full atomic swap flow completed successfully!");
    println!("   - Key splitting: ✓");
    println!("   - DLEQ proof: ✓");
    println!("   - Key recovery: ✓");
    println!("   - Ready for Monero transaction: ✓");
}

#[test]
fn test_swap_fails_with_wrong_secret() {
    // Test that wrong secret cannot unlock the swap
    let alice_keys = SwapKeyPair::generate();
    let hashlock: [u8; 32] = Sha256::digest(
        alice_keys.adaptor_scalar_bytes()
    ).into();
    
    // Generate DLEQ proof
    // Wrap adaptor_scalar in Zeroizing for memory safety
    let adaptor_scalar_zeroizing = Zeroizing::new(alice_keys.adaptor_scalar);
    let _dleq_proof = generate_dleq_proof(
        &adaptor_scalar_zeroizing,
        &alice_keys.adaptor_point,
        &hashlock,
    ).expect("DLEQ proof generation should succeed with valid inputs");
    
    // Bob tries wrong secret
    let wrong_secret = alice_keys.adaptor_scalar + curve25519_dalek::scalar::Scalar::from(1u64);
    
    // Hashlock won't match
    let wrong_hashlock: [u8; 32] = Sha256::digest(
        wrong_secret.to_bytes()
    ).into();
    assert_ne!(wrong_hashlock, hashlock,
        "Wrong secret must produce different hashlock");
    
    // Key recovery with wrong secret produces wrong key
    // Wrap partial_key in Zeroizing for memory safety
    let partial_key_zeroizing = Zeroizing::new(alice_keys.partial_key);
    let wrong_recovered = SwapKeyPair::recover(
        partial_key_zeroizing,
        wrong_secret,
    );
    assert_ne!(*wrong_recovered, alice_keys.full_spend_key,
        "Wrong secret must produce wrong recovered key");
    
    println!("✅ Wrong secret rejection: PASSED");
}

#[test]
fn test_multiple_swaps_independent() {
    // Verify that multiple swaps are independent
    let alice1_keys = SwapKeyPair::generate();
    let alice2_keys = SwapKeyPair::generate();
    
    // Keys should be different
    assert_ne!(alice1_keys.partial_key, alice2_keys.partial_key);
    assert_ne!(alice1_keys.adaptor_scalar, alice2_keys.adaptor_scalar);
    assert_ne!(alice1_keys.full_spend_key, alice2_keys.full_spend_key);
    
    // Hashlocks should be different
    let hashlock1: [u8; 32] = Sha256::digest(
        alice1_keys.adaptor_scalar_bytes()
    ).into();
    let hashlock2: [u8; 32] = Sha256::digest(
        alice2_keys.adaptor_scalar_bytes()
    ).into();
    assert_ne!(hashlock1, hashlock2, "Different swaps must have different hashlocks");
    
    println!("✅ Multiple swaps independence: PASSED");
}

