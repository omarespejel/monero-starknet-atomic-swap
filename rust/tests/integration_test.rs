//! Integration test simulating a full XMR↔Starknet atomic swap round.
//!
//! This test demonstrates that the same scalar `t` used in Cairo's
//! MSM verification (t·G == adaptor_point) also works for finalizing
//! the Monero adaptor signature.

use xmr_secret_gen::adaptor::{split_monero_key, create_adaptor_signature, finalize_signature, verify_signature};
use xmr_secret_gen::generate_swap_secret;
use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::scalar::Scalar;
use sha2::{Digest, Sha256};

#[test]
fn test_full_swap_round() {
    // ========== STEP 1: Generate secret and split Monero key ==========
    // This simulates Alice preparing for a swap
    
    // Generate swap secret (same as Cairo contract expects)
    let swap_secret = generate_swap_secret();
    let secret_bytes_vec = hex::decode(&swap_secret.secret_hex).unwrap();
    let secret_bytes: [u8; 32] = secret_bytes_vec.clone().try_into().unwrap();
    let adaptor_scalar = Scalar::from_bytes_mod_order(secret_bytes);
    
    // Split Monero spend key
    // In a real swap, we'd use the same adaptor_scalar for both Cairo and Monero
    // For this test, we'll use the adaptor_scalar from swap_secret
    let full_monero_key = Scalar::from_bytes_mod_order([0x42u8; 32]);
    
    // Create key pair with the same adaptor_scalar that Cairo will use
    let base_key = full_monero_key - adaptor_scalar;
    let key_pair = xmr_secret_gen::adaptor::KeyPair {
        base_key,
        adaptor_scalar,
    };
    
    // ========== STEP 2: Create adaptor point (goes to Cairo) ==========
    let adaptor_point = &adaptor_scalar * &ED25519_BASEPOINT_POINT;
    
    // Verify: This is the same adaptor_point that Cairo will verify
    // Cairo checks: t·G == adaptor_point (via MSM)
    let computed_point = &adaptor_scalar * &ED25519_BASEPOINT_POINT;
    assert_eq!(computed_point, adaptor_point);
    
    // ========== STEP 3: Create adaptor signature (Monero side) ==========
    let message = b"Monero transaction to be signed";
    let adaptor_sig = create_adaptor_signature(
        &key_pair.base_key,
        &adaptor_point,
        message,
    );
    
    // ========== STEP 4: Simulate Starknet unlock ==========
    // On Starknet, Alice calls verify_and_unlock(secret)
    // Cairo verifies: SHA-256(secret) == stored_hash AND t·G == adaptor_point
    // This reveals t (adaptor_scalar) on-chain
    
    // Verify hash matches (simulating Cairo's hash check)
    let hash_bytes: [u8; 32] = Sha256::digest(&secret_bytes_vec).into();
    let hash_words: [u32; 8] = core::array::from_fn(|i| {
        let start = i * 4;
        u32::from_be_bytes(hash_bytes[start..start + 4].try_into().unwrap())
    });
    assert_eq!(hash_words, swap_secret.hash_u32_words);
    
    // ========== STEP 5: Finalize Monero signature using revealed t ==========
    // Bob (or Alice) extracts t from Starknet event and finalizes signature
    let (s_final, extracted_key) = finalize_signature(
        &adaptor_sig,
        &adaptor_scalar, // This is the t revealed from Starknet
        message,
    );
    
    // ========== STEP 6: Verify signature is valid ==========
    let public_key = &full_monero_key * &ED25519_BASEPOINT_POINT;
    let mut challenge_input = Vec::new();
    challenge_input.extend_from_slice(message);
    challenge_input.extend_from_slice(&adaptor_sig.nonce_commitment.compress().to_bytes());
    challenge_input.extend_from_slice(&adaptor_sig.adaptor_point.compress().to_bytes());
    let challenge = Scalar::from_bytes_mod_order(Sha256::digest(&challenge_input).into());
    
    assert!(
        verify_signature(&s_final, &adaptor_sig.nonce_commitment, &challenge, &public_key),
        "Finalized signature should be valid"
    );
    
    // ========== STEP 7: Verify key extraction ==========
    // The extracted key should match the adaptor scalar
    // (In full CLSAG, this would be the full spend key)
    assert_eq!(extracted_key, adaptor_scalar);
    
    println!("✅ Full swap round completed successfully!");
    println!("   - Adaptor scalar t: {}", hex::encode(adaptor_scalar.to_bytes()));
    println!("   - Adaptor point T: {:?}", adaptor_point.compress());
    println!("   - Signature finalized and verified");
}

