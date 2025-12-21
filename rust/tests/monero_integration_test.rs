use xmr_secret_gen::monero::{wait_for_finality, MoneroWalletClient};
use xmr_secret_gen::monero_wallet::MoneroWallet;

#[tokio::test]
#[ignore] // Run with: cargo test --ignored
async fn test_wait_for_finality_live_stagenet() {
    // Requires wallet-rpc running on stagenet with a known confirmed tx
    let client = MoneroWallet::new(
        "http://localhost:38088/json_rpc".to_string(),
        "http://stagenet.xmr-tw.org:38081/json_rpc".to_string(),
        "test_wallet".to_string(),
        "./wallets".to_string(),
    )
    .await
    .expect("Failed to create Monero wallet client");

    // Use a known confirmed stagenet txid (replace with real one)
    let txid = "your_confirmed_stagenet_txid_here";
    
    let result = wait_for_finality(&client, txid, 1, 5, 60).await;
    
    assert!(result.is_ok(), "Should find confirmed tx: {:?}", result);
    println!("Transaction info: {:?}", result.unwrap());
}
