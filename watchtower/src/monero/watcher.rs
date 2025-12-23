//! Monero transaction watcher and reorg detection

use anyhow::{anyhow, Result};
use std::time::{Duration, Instant};
use tracing::{error, info, warn};

/// Monitoring duration: grace period (2 hours) + 1 hour buffer
const MONITORING_DURATION_SECS: u64 = 7200 + 3600;

/// Transaction information from Monero daemon
#[derive(Debug, Clone)]
pub struct TxInfo {
    pub block_height: u64,
    pub confirmations: u64,
}

/// Monitor a Monero transaction for reorgs.
///
/// This function continuously monitors a Monero transaction to detect if it
/// gets reorganized to a different block height. It runs for the grace period
/// duration plus a 1-hour buffer.
///
/// # Arguments
/// * `swap_id` - Identifier for the swap (for logging)
/// * `txid` - Monero transaction ID to monitor
/// * `original_height` - Original block height when transaction was first seen
/// * `daemon_url` - Monero daemon RPC URL
///
/// # Returns
/// Returns `Ok(())` if monitoring completes without detecting a reorg.
/// Returns `Err` if a reorg is detected or the transaction disappears.
pub async fn monitor_monero_tx(
    swap_id: &str,
    txid: &str,
    original_height: u64,
    daemon_url: &str,
) -> Result<()> {
    let start = Instant::now();

    info!(
        "[{}] Starting Monero reorg monitoring for TX {} (original height: {})",
        swap_id, txid, original_height
    );

    loop {
        if start.elapsed().as_secs() > MONITORING_DURATION_SECS {
            info!(
                "[{}] Monitoring period complete for TX {}",
                swap_id, txid
            );
            return Ok(());
        }

        match get_tx_info(daemon_url, txid).await {
            Ok(Some(info)) => {
                if info.block_height != original_height {
                    error!(
                        "[{}] REORG DETECTED! TX {} moved from height {} to {}",
                        swap_id, txid, original_height, info.block_height
                    );
                    // TODO: Send alert (webhook, email, etc.)
                    return Err(anyhow!(
                        "Monero reorg detected: TX {} moved from height {} to {}",
                        txid,
                        original_height,
                        info.block_height
                    ));
                }
                // Transaction still at original height - continue monitoring
            }
            Ok(None) => {
                error!(
                    "[{}] TX {} vanished from chain!",
                    swap_id, txid
                );
                return Err(anyhow!("Monero transaction {} not found", txid));
            }
            Err(e) => {
                warn!(
                    "[{}] Failed to query daemon for TX {}: {}",
                    swap_id, txid, e
                );
                // Continue monitoring on transient errors
            }
        }

        tokio::time::sleep(Duration::from_secs(60)).await;
    }
}

/// Get transaction information from Monero daemon.
///
/// # Arguments
/// * `daemon_url` - Monero daemon RPC URL
/// * `txid` - Transaction ID (hex string)
///
/// # Returns
/// `Ok(Some(TxInfo))` if transaction is found and confirmed
/// `Ok(None)` if transaction is not found
/// `Err` on RPC errors
async fn get_tx_info(daemon_url: &str, txid: &str) -> Result<Option<TxInfo>> {
    let client = reqwest::Client::new();
    let resp: serde_json::Value = client
        .post(daemon_url)
        .json(&serde_json::json!({
            "jsonrpc": "2.0",
            "id": "0",
            "method": "get_transactions",
            "params": {
                "txs_hashes": [txid],
                "decode_as_json": false
            }
        }))
        .send()
        .await?
        .json()
        .await?;

    // Check for RPC error
    if let Some(error) = resp.get("error") {
        let error_msg = error.get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown RPC error");
        return Err(anyhow!("Monero RPC error: {}", error_msg));
    }

    // Parse response
    let txs = resp
        .get("result")
        .and_then(|r| r.get("txs"))
        .and_then(|t| t.as_array())
        .ok_or_else(|| anyhow!("Invalid response format from Monero daemon"))?;

    if txs.is_empty() {
        return Ok(None);
    }

    let tx = &txs[0];
    
    // Check if transaction is in a block
    let block_height = tx
        .get("block_height")
        .and_then(|h| h.as_u64());

    if let Some(height) = block_height {
        // Get current block height to calculate confirmations
        let current_height = get_current_block_height(daemon_url).await?;
        let confirmations = current_height.saturating_sub(height) + 1;

        Ok(Some(TxInfo {
            block_height: height,
            confirmations,
        }))
    } else {
        // Transaction exists but not yet in a block
        Ok(None)
    }
}

/// Get current Monero block height from daemon.
async fn get_current_block_height(daemon_url: &str) -> Result<u64> {
    let client = reqwest::Client::new();
    let resp: serde_json::Value = client
        .post(daemon_url)
        .json(&serde_json::json!({
            "jsonrpc": "2.0",
            "id": "0",
            "method": "get_block_count"
        }))
        .send()
        .await?
        .json()
        .await?;

    if let Some(error) = resp.get("error") {
        let error_msg = error.get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown RPC error");
        return Err(anyhow!("Monero RPC error: {}", error_msg));
    }

    let count = resp
        .get("result")
        .and_then(|r| r.get("count"))
        .and_then(|c| c.as_u64())
        .ok_or_else(|| anyhow!("Invalid response format from Monero daemon"))?;

    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[tokio::test]
    #[ignore] // Requires Monero daemon
    async fn test_get_current_block_height() {
        let height = get_current_block_height("http://localhost:18081").await;
        match height {
            Ok(h) => println!("Current height: {}", h),
            Err(e) => println!("Error: {}", e),
        }
    }
}
