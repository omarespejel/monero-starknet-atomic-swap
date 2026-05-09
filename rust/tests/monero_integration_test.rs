use xmr_secret_gen::monero::{wait_for_finality, MoneroWalletClient};
use xmr_secret_gen::monero_wallet::MoneroWallet;

fn wallet_rpc_url() -> String {
    std::env::var("MONERO_WALLET_RPC_URL")
        .unwrap_or_else(|_| "http://127.0.0.1:38090/json_rpc".to_string())
}

fn daemon_rpc_url() -> String {
    std::env::var("MONERO_DAEMON_RPC_URL")
        .unwrap_or_else(|_| "http://node2.monerodevs.org:38089/json_rpc".to_string())
}

#[tokio::test]
#[ignore] // Run with: cargo test --ignored
async fn test_wait_for_finality_live_stagenet() {
    // Requires wallet-rpc running on stagenet with a known confirmed tx
    let client = MoneroWallet::new(
        wallet_rpc_url(),
        daemon_rpc_url(),
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
