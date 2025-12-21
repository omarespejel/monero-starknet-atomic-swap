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

