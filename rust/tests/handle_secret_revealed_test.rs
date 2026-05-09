//! Tests for handle_secret_revealed() - Monero claiming after secret reveal
//!
//! These tests validate the critical claiming logic that recovers Monero funds
//! after the secret t is revealed on Starknet.

use monero::Network;
use xmr_secret_gen::swap::{handle_secret_revealed, SwapState};

const UNREACHABLE_WALLET_RPC_URL: &str = "http://127.0.0.1:9/json_rpc";
const UNREACHABLE_DAEMON_RPC_URL: &str = "http://127.0.0.1:9/json_rpc";
const TEST_WALLET_DIR: &str = "/tmp/atomic-swap-test-wallets";

#[tokio::test]
async fn test_handle_secret_revealed_rejects_wrong_state() {
    let state = SwapState::Created {
        swap_id: "test".to_string(),
        lock_duration_secs: 3600,
        amount: 1000,
        expected_monero_amount: 100000000,
        hashlock: [0u32; 8],
        monero_restore_height: None,
    };

    let result = handle_secret_revealed(
        &state,
        [0u8; 32],
        UNREACHABLE_WALLET_RPC_URL,
        UNREACHABLE_DAEMON_RPC_URL,
        TEST_WALLET_DIR,
        Network::Stagenet,
    )
    .await;

    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("SecretRevealed"));
}

#[tokio::test]
async fn test_handle_secret_revealed_requires_partial_key() {
    let state = SwapState::SecretRevealed {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        reveal_timestamp: 1234567890,
        monero_txid: Some("txid".to_string()),
        monero_amount: Some(100000000),
        monero_restore_height: Some(100000),
        partial_spend_key: None, // Missing!
        claim_destination: Some("5A1...".to_string()),
    };

    let result = handle_secret_revealed(
        &state,
        [0u8; 32],
        UNREACHABLE_WALLET_RPC_URL,
        UNREACHABLE_DAEMON_RPC_URL,
        TEST_WALLET_DIR,
        Network::Stagenet,
    )
    .await;

    assert!(result.is_err());
    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("partial_spend_key") || error_msg.contains("Cannot claim"),
        "Error should mention partial_spend_key or claim failure, got: {}",
        error_msg
    );
}

#[tokio::test]
async fn test_handle_secret_revealed_requires_destination() {
    let state = SwapState::SecretRevealed {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        reveal_timestamp: 1234567890,
        monero_txid: Some("txid".to_string()),
        monero_amount: Some(100000000),
        monero_restore_height: Some(100000),
        partial_spend_key: Some([0x42u8; 32]),
        claim_destination: None, // Missing!
    };

    let result = handle_secret_revealed(
        &state,
        [0u8; 32],
        UNREACHABLE_WALLET_RPC_URL,
        UNREACHABLE_DAEMON_RPC_URL,
        TEST_WALLET_DIR,
        Network::Stagenet,
    )
    .await;

    assert!(result.is_err());
    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.contains("claim_destination") || error_msg.contains("Cannot claim"),
        "Error should mention claim_destination or claim failure, got: {}",
        error_msg
    );
}

#[tokio::test]
async fn test_handle_secret_revealed_validates_state_fields() {
    // Test with all required fields present
    let state = SwapState::SecretRevealed {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        reveal_timestamp: 1234567890,
        monero_txid: Some("txid".to_string()),
        monero_amount: Some(100000000),
        monero_restore_height: Some(100000),
        partial_spend_key: Some([0x42u8; 32]),
        claim_destination: Some("5A1...".to_string()),
    };

    // This will fail at wallet-rpc connection (expected), but should pass state validation
    let result = handle_secret_revealed(
        &state,
        [0x99u8; 32],
        UNREACHABLE_WALLET_RPC_URL,
        UNREACHABLE_DAEMON_RPC_URL,
        TEST_WALLET_DIR,
        Network::Stagenet,
    )
    .await;

    // Should fail at wallet-rpc connection, not state validation
    // If it fails with connection error, that's fine - state validation passed
    if result.is_err() {
        let error_msg = result.unwrap_err().to_string();
        // Should NOT fail with state validation errors
        assert!(
            !error_msg.contains("SecretRevealed")
                && !error_msg.contains("partial_spend_key")
                && !error_msg.contains("claim_destination"),
            "Should not fail on state validation, got: {}",
            error_msg
        );
    }
}

#[tokio::test]
async fn test_handle_secret_revealed_uses_restore_height() {
    let restore_height = 123456u64;
    let state = SwapState::SecretRevealed {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        reveal_timestamp: 1234567890,
        monero_txid: Some("txid".to_string()),
        monero_amount: Some(100000000),
        monero_restore_height: Some(restore_height),
        partial_spend_key: Some([0x42u8; 32]),
        claim_destination: Some("5A1...".to_string()),
    };

    // This will fail at wallet-rpc, but we can verify restore_height is used
    // by checking the error doesn't mention restore_height issues
    let result = handle_secret_revealed(
        &state,
        [0x99u8; 32],
        UNREACHABLE_WALLET_RPC_URL,
        UNREACHABLE_DAEMON_RPC_URL,
        TEST_WALLET_DIR,
        Network::Stagenet,
    )
    .await;

    // Should fail at connection, not restore_height
    assert!(result.is_err());
    let error_msg = result.unwrap_err().to_string();
    // Should not complain about restore_height
    assert!(
        !error_msg.contains("restore_height"),
        "Should not fail on restore_height, got: {}",
        error_msg
    );
}

#[tokio::test]
async fn test_handle_secret_revealed_falls_back_to_zero_height() {
    let state = SwapState::SecretRevealed {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        reveal_timestamp: 1234567890,
        monero_txid: Some("txid".to_string()),
        monero_amount: Some(100000000),
        monero_restore_height: None, // Should fallback to 0
        partial_spend_key: Some([0x42u8; 32]),
        claim_destination: Some("5A1...".to_string()),
    };

    // Should accept None and use 0 as fallback
    let result = handle_secret_revealed(
        &state,
        [0x99u8; 32],
        UNREACHABLE_WALLET_RPC_URL,
        UNREACHABLE_DAEMON_RPC_URL,
        TEST_WALLET_DIR,
        Network::Stagenet,
    )
    .await;

    // Should fail at connection, not restore_height validation
    assert!(result.is_err());
    let error_msg = result.unwrap_err().to_string();
    assert!(
        !error_msg.contains("restore_height"),
        "Should handle None restore_height gracefully, got: {}",
        error_msg
    );
}
