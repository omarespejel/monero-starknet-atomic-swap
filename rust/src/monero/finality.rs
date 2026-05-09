//! Monero transaction finality helpers.
//!
//! Waits for a transaction to reach a minimum number of confirmations
//! before considering it final. Default threshold: 10 confirmations (~20 min).

use anyhow::{anyhow, Result};
use std::time::Duration;
use tokio::time::sleep;

use crate::monero_wallet::types::TransferInfo;

/// Trait for Monero wallet operations (enables mocking).
#[async_trait::async_trait]
pub trait MoneroWalletClient: Send + Sync {
    /// Get transfer details by transaction ID.
    async fn get_transfer_by_txid(&self, txid: &str) -> Result<TransferInfo>;
}

/// Default number of confirmations for finality (Monerica recommendation).
pub const DEFAULT_CONFIRMATIONS: u64 = 10;

/// Default poll interval in seconds.
pub const DEFAULT_POLL_INTERVAL_SECS: u64 = 20;

/// Maximum consecutive RPC errors before aborting (prevents log flooding).
const MAX_CONSECUTIVE_ERRORS: u32 = 10;

/// Wait until a transaction has at least `min_confirmations`.
///
/// # Arguments
/// * `client` - Monero wallet client (real or mock)
/// * `txid` - Transaction ID to monitor
/// * `min_confirmations` - Required confirmations (default: 10)
/// * `poll_interval_secs` - Seconds between polls (default: 20)
/// * `timeout_secs` - Maximum wait time before error (0 = no timeout)
///
/// # Returns
/// * `Ok(TransferInfo)` - Transaction details once finality reached
/// * `Err` - If timeout exceeded, too many consecutive RPC errors, or other error
///
/// # Error Handling
/// - Transient RPC errors are logged but don't abort (up to `MAX_CONSECUTIVE_ERRORS`)
/// - After `MAX_CONSECUTIVE_ERRORS` consecutive errors, function returns error
/// - Timeout (if enabled) is checked before each poll attempt
pub async fn wait_for_finality<C: MoneroWalletClient>(
    client: &C,
    txid: &str,
    min_confirmations: u64,
    poll_interval_secs: u64,
    timeout_secs: u64,
) -> Result<TransferInfo> {
    let start = std::time::Instant::now();
    let mut consecutive_errors = 0u32;

    loop {
        // Check timeout
        if timeout_secs > 0 && start.elapsed().as_secs() > timeout_secs {
            return Err(anyhow!(
                "Timeout waiting for {} confirmations on tx {}",
                min_confirmations,
                txid
            ));
        }

        // Poll transaction status
        match client.get_transfer_by_txid(txid).await {
            Ok(info) => {
                // Reset error counter on successful poll
                consecutive_errors = 0;

                if info.confirmations >= min_confirmations {
                    return Ok(info);
                }
                // Not enough confirmations yet, continue polling
            }
            Err(e) => {
                consecutive_errors += 1;
                tracing::warn!(
                    "Error polling tx {} ({}/{}): {}",
                    txid,
                    consecutive_errors,
                    MAX_CONSECUTIVE_ERRORS,
                    e
                );

                // Abort if too many consecutive errors (prevents log flooding)
                if consecutive_errors >= MAX_CONSECUTIVE_ERRORS {
                    return Err(anyhow!(
                        "Too many consecutive RPC errors ({}/{}) for tx {}",
                        consecutive_errors,
                        MAX_CONSECUTIVE_ERRORS,
                        txid
                    ));
                }
            }
        }

        sleep(Duration::from_secs(poll_interval_secs)).await;
    }
}

/// Convenience wrapper with default parameters.
pub async fn wait_for_default_finality<C: MoneroWalletClient>(
    client: &C,
    txid: &str,
) -> Result<TransferInfo> {
    wait_for_finality(
        client,
        txid,
        DEFAULT_CONFIRMATIONS,
        DEFAULT_POLL_INTERVAL_SECS,
        0, // no timeout
    )
    .await
}
