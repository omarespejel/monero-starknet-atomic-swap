use anyhow::Result;
use async_trait::async_trait;
use mockall::mock;
use mockall::predicate::*;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

// Import from your crate
use xmr_secret_gen::monero::finality::{
    wait_for_finality, MoneroWalletClient,
};
use xmr_secret_gen::monero_wallet::types::TransferInfo;

// Generate mock
mock! {
    pub WalletClient {}
    
    #[async_trait]
    impl MoneroWalletClient for WalletClient {
        async fn get_transfer_by_txid(&self, txid: &str) -> Result<TransferInfo>;
    }
}

#[tokio::test]
async fn test_returns_immediately_when_already_confirmed() {
    let mut mock = MockWalletClient::new();
    
    mock.expect_get_transfer_by_txid()
        .with(eq("test_txid"))
        .times(1)
        .returning(|txid| Ok(TransferInfo {
            txid: txid.to_string(),
            confirmations: 15,
            height: 12345,
            amount: 1000000,
            unlock_time: 0,
        }));

    let result = wait_for_finality(&mock, "test_txid", 10, 0, 0).await;
    
    assert!(result.is_ok());
    assert_eq!(result.unwrap().confirmations, 15);
}

#[tokio::test]
async fn test_polls_until_threshold_reached() {
    let call_count = Arc::new(AtomicU64::new(0));
    let call_count_clone = call_count.clone();
    
    let mut mock = MockWalletClient::new();
    
    mock.expect_get_transfer_by_txid()
        .with(eq("test_txid"))
        .times(3)
        .returning(move |txid| {
            let count = call_count_clone.fetch_add(1, Ordering::SeqCst);
            let confirmations = match count {
                0 => 3,
                1 => 7,
                _ => 10,
            };
            Ok(TransferInfo {
                txid: txid.to_string(),
                confirmations,
                height: 12345 + count,
                amount: 1000000,
                unlock_time: 0,
            })
        });

    // poll_interval = 0 for fast test
    let result = wait_for_finality(&mock, "test_txid", 10, 0, 0).await;
    
    assert!(result.is_ok());
    assert_eq!(result.unwrap().confirmations, 10);
    assert_eq!(call_count.load(Ordering::SeqCst), 3);
}

#[tokio::test]
async fn test_timeout_returns_error() {
    let mut mock = MockWalletClient::new();
    
    // Always return 0 confirmations
    mock.expect_get_transfer_by_txid()
        .returning(|txid| Ok(TransferInfo {
            txid: txid.to_string(),
            confirmations: 0,
            height: 0,
            amount: 0,
            unlock_time: 0,
        }));

    // Very short timeout
    let result = wait_for_finality(&mock, "test_txid", 10, 0, 1).await;
    
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("Timeout"));
}

#[tokio::test]
async fn test_continues_on_transient_rpc_error() {
    let call_count = Arc::new(AtomicU64::new(0));
    let call_count_clone = call_count.clone();
    
    let mut mock = MockWalletClient::new();
    
    mock.expect_get_transfer_by_txid()
        .times(3)
        .returning(move |txid| {
            let count = call_count_clone.fetch_add(1, Ordering::SeqCst);
            match count {
                0 => Err(anyhow::anyhow!("Connection refused")),
                1 => Ok(TransferInfo {
                    txid: txid.to_string(),
                    confirmations: 5,
                    height: 100,
                    amount: 1000000,
                    unlock_time: 0,
                }),
                _ => Ok(TransferInfo {
                    txid: txid.to_string(),
                    confirmations: 10,
                    height: 105,
                    amount: 1000000,
                    unlock_time: 0,
                }),
            }
        });

    let result = wait_for_finality(&mock, "test_txid", 10, 0, 60).await;
    
    assert!(result.is_ok());
    assert_eq!(call_count.load(Ordering::SeqCst), 3);
}

#[tokio::test]
async fn test_no_timeout_when_timeout_secs_is_zero() {
    let call_count = Arc::new(AtomicU64::new(0));
    let call_count_clone = call_count.clone();
    
    let mut mock = MockWalletClient::new();
    
    // Return 0 confirmations many times (simulating long wait)
    mock.expect_get_transfer_by_txid()
        .times(5)
        .returning(move |txid| {
            let count = call_count_clone.fetch_add(1, Ordering::SeqCst);
            Ok(TransferInfo {
                txid: txid.to_string(),
                confirmations: if count < 4 { 0 } else { 10 },
                height: 100 + count,
                amount: 1000000,
                unlock_time: 0,
            })
        });

    // timeout_secs = 0 means no timeout
    let result = wait_for_finality(&mock, "test_txid", 10, 0, 0).await;
    
    assert!(result.is_ok());
    assert_eq!(result.unwrap().confirmations, 10);
}

#[tokio::test]
async fn test_fast_polling_with_zero_interval() {
    let call_count = Arc::new(AtomicU64::new(0));
    let call_count_clone = call_count.clone();
    
    let mut mock = MockWalletClient::new();
    
    mock.expect_get_transfer_by_txid()
        .times(3)
        .returning(move |txid| {
            let count = call_count_clone.fetch_add(1, Ordering::SeqCst);
            Ok(TransferInfo {
                txid: txid.to_string(),
                confirmations: match count {
                    0 => 3,
                    1 => 7,
                    _ => 10,
                },
                height: 100 + count,
                amount: 1000000,
                unlock_time: 0,
            })
        });

    // poll_interval_secs = 0 for fast polling (useful in tests)
    let result = wait_for_finality(&mock, "test_txid", 10, 0, 0).await;
    
    assert!(result.is_ok());
    assert_eq!(result.unwrap().confirmations, 10);
}

#[tokio::test]
async fn test_aborts_after_max_consecutive_errors() {
    let mut mock = MockWalletClient::new();
    
    // Always return error (simulating daemon down)
    mock.expect_get_transfer_by_txid()
        .times(10) // MAX_CONSECUTIVE_ERRORS
        .returning(|_txid| Err(anyhow::anyhow!("Connection refused")));

    let result = wait_for_finality(&mock, "test_txid", 10, 0, 60).await;
    
    assert!(result.is_err());
    let error_msg = result.unwrap_err().to_string();
    assert!(error_msg.contains("Too many consecutive RPC errors"));
    assert!(error_msg.contains("10")); // MAX_CONSECUTIVE_ERRORS
}

#[tokio::test]
async fn test_resets_error_counter_on_success() {
    let call_count = Arc::new(AtomicU64::new(0));
    let call_count_clone = call_count.clone();
    
    let mut mock = MockWalletClient::new();
    
    // Pattern: error, success (resets counter), error, error, ..., success
    mock.expect_get_transfer_by_txid()
        .times(12)
        .returning(move |txid| {
            let count = call_count_clone.fetch_add(1, Ordering::SeqCst);
            match count {
                0 => Err(anyhow::anyhow!("First error")),
                1 => Ok(TransferInfo {
                    txid: txid.to_string(),
                    confirmations: 5, // Not enough yet
                    height: 100,
                    amount: 1000000,
                    unlock_time: 0,
                }),
                2..=10 => Err(anyhow::anyhow!("Subsequent errors")), // 9 more errors
                11 => Ok(TransferInfo {
                    txid: txid.to_string(),
                    confirmations: 10, // Finally enough
                    height: 105,
                    amount: 1000000,
                    unlock_time: 0,
                }),
                _ => Err(anyhow::anyhow!("Should not reach here")),
            }
        });

    // Should succeed because error counter resets after first success
    let result = wait_for_finality(&mock, "test_txid", 10, 0, 60).await;
    
    assert!(result.is_ok());
    assert_eq!(result.unwrap().confirmations, 10);
}

