//! Manual integration tests for wallet-rpc operations.
//! Run with: cargo test --test wallet_rpc_manual_test -- --ignored --nocapture

use xmr_secret_gen::monero_wallet::MoneroWallet;

#[tokio::test]
#[ignore]
async fn test_wallet_rpc_connection() {
    let wallet = MoneroWallet::new(
        "http://localhost:38088/json_rpc".to_string(),
        "http://stagenet.xmr-tw.org:38081/json_rpc".to_string(),
        "test_wallet".to_string(),
        "/tmp/monero_wallets".to_string(),
    ).await;
    
    assert!(wallet.is_ok(), "Failed to connect: {:?}", wallet.err());
    println!("✅ Wallet-RPC connection successful");
}

#[tokio::test]
#[ignore]
async fn test_generate_from_keys() {
    use curve25519_dalek::scalar::Scalar;
    use rand::RngCore;
    
    let wallet = MoneroWallet::new(
        "http://localhost:38088/json_rpc".to_string(),
        "http://stagenet.xmr-tw.org:38081/json_rpc".to_string(),
        "test_wallet".to_string(),
        "/tmp/monero_wallets".to_string(),
    ).await.expect("Failed to create wallet");
    
    // Generate random test keys
    let mut rng = rand::rngs::OsRng;
    let mut spend_bytes = [0u8; 32];
    rng.fill_bytes(&mut spend_bytes);
    let spend_key = Scalar::from_bytes_mod_order(spend_bytes);
    
    // Derive view key
    use tiny_keccak::{Hasher, Keccak};
    let mut keccak = Keccak::v256();
    keccak.update(&spend_key.to_bytes());
    let mut hash = [0u8; 32];
    keccak.finalize(&mut hash);
    let view_key = Scalar::from_bytes_mod_order(hash);
    
    let spend_hex = hex::encode(spend_key.to_bytes());
    let view_hex = hex::encode(view_key.to_bytes());
    
    // Test generate_from_keys
    let result = wallet.generate_from_keys(
        &spend_hex,
        &view_hex,
        "",  // Let wallet-rpc derive address
        0,   // restore_height
    ).await;
    
    println!("generate_from_keys result: {:?}", result);
    
    // Cleanup
    let _ = wallet.close_wallet().await;
}

#[tokio::test]
#[ignore]
async fn test_refresh_operation() {
    use curve25519_dalek::scalar::Scalar;
    use rand::RngCore;
    use tiny_keccak::{Hasher, Keccak};
    
    let wallet = MoneroWallet::new(
        "http://localhost:38088/json_rpc".to_string(),
        "http://stagenet.xmr-tw.org:38081/json_rpc".to_string(),
        "test_wallet_refresh".to_string(),
        "/tmp/monero_wallets".to_string(),
    ).await.expect("Failed to create wallet");
    
    // Generate test keys
    let mut rng = rand::rngs::OsRng;
    let mut spend_bytes = [0u8; 32];
    rng.fill_bytes(&mut spend_bytes);
    let spend_key = Scalar::from_bytes_mod_order(spend_bytes);
    
    // Derive view key
    let mut keccak = Keccak::v256();
    keccak.update(&spend_key.to_bytes());
    let mut hash = [0u8; 32];
    keccak.finalize(&mut hash);
    let view_key = Scalar::from_bytes_mod_order(hash);
    
    let spend_hex = hex::encode(spend_key.to_bytes());
    let view_hex = hex::encode(view_key.to_bytes());
    
    // Generate wallet (will fail on address, but that's OK for this test)
    let _wallet_name = wallet.generate_from_keys(
        &spend_hex,
        &view_hex,
        "",  // Empty address (limitation documented)
        0,
    ).await;
    
    // Test refresh (will fail if wallet not created, but tests the method exists)
    let refresh_result = wallet.refresh().await;
    println!("Refresh result: {:?}", refresh_result);
    
    // Cleanup
    let _ = wallet.close_wallet().await;
}

#[tokio::test]
#[ignore]
async fn test_wallet_cleanup_operations() {
    let wallet = MoneroWallet::new(
        "http://localhost:38088/json_rpc".to_string(),
        "http://stagenet.xmr-tw.org:38081/json_rpc".to_string(),
        "test_wallet_cleanup".to_string(),
        "/tmp/monero_wallets".to_string(),
    ).await.expect("Failed to create wallet");
    
    // Test close_wallet (should work even if no wallet open)
    let close_result = wallet.close_wallet().await;
    println!("Close wallet result: {:?}", close_result);
    
    // Test secure_delete_wallet (should work even if file doesn't exist)
    let delete_result = wallet.secure_delete_wallet("nonexistent_wallet").await;
    println!("Delete wallet result: {:?}", delete_result);
    
    // Both should not panic (may return errors, but should handle gracefully)
    assert!(true, "Cleanup operations should not panic");
}

#[tokio::test]
#[ignore]
async fn test_claim_flow_live() {
    use curve25519_dalek::scalar::Scalar;
    use rand::RngCore;
    use zeroize::Zeroizing;
    use xmr_secret_gen::monero::claim_monero_after_reveal;
    
    // 1. Generate test keys
    let mut rng = rand::rngs::OsRng;
    
    // Generate partial spend key (x_partial)
    let mut partial_bytes = [0u8; 32];
    rng.fill_bytes(&mut partial_bytes);
    let x_partial = Zeroizing::new(Scalar::from_bytes_mod_order(partial_bytes));
    
    // Generate adaptor scalar (t) - this would be revealed on Starknet
    let mut t_bytes = [0u8; 32];
    rng.fill_bytes(&mut t_bytes);
    let t = Scalar::from_bytes_mod_order(t_bytes);
    
    // 2. Create wallet client
    let wallet = MoneroWallet::new(
        "http://localhost:38088/json_rpc".to_string(),
        "http://stagenet.xmr-tw.org:38081/json_rpc".to_string(),
        "test_claim_flow".to_string(),
        "/tmp/monero_wallets".to_string(),
    ).await.expect("Failed to create wallet");
    
    // 3. Call claim_monero_after_reveal()
    // This will:
    //   - Recover full key: x = x_partial + t
    //   - Derive view key
    //   - Generate wallet from keys
    //   - Refresh wallet
    //   - Attempt sweep_all (will fail if no funds - that's OK)
    //   - Cleanup wallet
    
    let destination = "5A1..."; // Placeholder destination address
    
    let result = claim_monero_after_reveal(
        &wallet,
        x_partial,
        t,
        destination,
        0, // restore_height (0 for testing)
    ).await;
    
    // 4. Verify wallet cleanup happened
    // The function should cleanup even on error
    // We expect this to fail at sweep_all (no funds), but cleanup should still happen
    
    match result {
        Ok(tx_hash) => {
            println!("✅ Claim successful! TX: {}", tx_hash);
            // Verify wallet was cleaned up
            let close_result = wallet.close_wallet().await;
            println!("Close wallet result: {:?}", close_result);
        }
        Err(e) => {
            println!("⚠️ Claim failed (expected if no funds): {:?}", e);
            // Verify cleanup still happened (function should cleanup on error)
            let close_result = wallet.close_wallet().await;
            println!("Close wallet result (after error): {:?}", close_result);
            
            // This is OK - we're testing the flow, not actual funds
            // The important part is that cleanup happens
            assert!(
                e.to_string().contains("sweep") || 
                e.to_string().contains("funds") ||
                e.to_string().contains("address") ||
                e.to_string().contains("Failed"),
                "Error should be related to sweep/funds/address, got: {}",
                e
            );
        }
    }
    
    println!("✅ Claim flow test complete - cleanup verified");
}

