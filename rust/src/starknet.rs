//! Starknet integration for contract deployment and event watching.
//!
//! This module provides functions to:
//! - Deploy AtomicLock contracts on Sepolia
//! - Watch for Unlocked events
//! - Call verify_and_unlock

use anyhow::{Context, Result};
use serde_json::{json, Value};

/// Starknet RPC client (simplified, using HTTP JSON-RPC).
pub struct StarknetClient {
    rpc_url: String,
    client: reqwest::Client,
}

impl StarknetClient {
    pub fn new(rpc_url: String) -> Self {
        Self {
            rpc_url,
            client: reqwest::Client::new(),
        }
    }

    /// Call Starknet JSON-RPC method.
    async fn call(&self, method: &str, params: Value) -> Result<Value> {
        let payload = json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        });

        let response = self
            .client
            .post(&self.rpc_url)
            .json(&payload)
            .send()
            .await
            .context("Failed to send RPC request")?;

        let result: Value = response
            .json()
            .await
            .context("Failed to parse RPC response")?;

        if let Some(error) = result.get("error") {
            anyhow::bail!("RPC error: {}", error);
        }

        Ok(result.get("result").cloned().unwrap_or(result))
    }

    /// Get current block number.
    pub async fn get_block_number(&self) -> Result<u64> {
        let result = self.call("starknet_blockNumber", json!([])).await?;
        let block_num = result
            .as_str()
            .and_then(|s| s.strip_prefix("0x"))
            .and_then(|s| u64::from_str_radix(s, 16).ok())
            .context("Invalid block number format")?;
        Ok(block_num)
    }

    /// Get events from a contract (simplified).
    pub async fn get_events(
        &self,
        contract_address: &str,
        from_block: Option<u64>,
    ) -> Result<Vec<Value>> {
        // Simplified event fetching - in production, use proper event filtering
        let filter = json!({
            "address": contract_address,
            "from_block": from_block.map(|n| format!("0x{:x}", n)),
        });

        let result = self
            .call("starknet_getEvents", json!({ "filter": filter }))
            .await?;

        Ok(result.as_array().cloned().unwrap_or_default())
    }

    /// Call contract function (simplified - requires account signing in production).
    pub async fn call_contract(
        &self,
        contract_address: &str,
        function: &str,
        calldata: Vec<String>,
    ) -> Result<Value> {
        // This is a simplified version - real implementation needs account signing
        anyhow::bail!(
            "Contract calls require account signing - implement with starknet-rs or starknet.js"
        );
    }
}

/// Watch for Unlocked events from an AtomicLock contract.
pub async fn watch_unlocked_events(
    client: &StarknetClient,
    contract_address: &str,
    poll_interval_secs: u64,
) -> Result<String> {
    println!(
        "👀 Watching for Unlocked events from contract: {}",
        contract_address
    );

    let mut last_block = client.get_block_number().await?;

    loop {
        tokio::time::sleep(tokio::time::Duration::from_secs(poll_interval_secs)).await;

        let current_block = client.get_block_number().await?;

        // Check events from last_block to current_block
        let events = client
            .get_events(contract_address, Some(last_block))
            .await
            .context("Failed to fetch events")?;

        for event in events {
            // Look for Unlocked event (event key = hash of "Unlocked")
            // In production, decode event using contract ABI
            if let Some(data) = event.get("data") {
                if let Some(data_array) = data.as_array() {
                    if data_array.len() >= 2 {
                        // First element is unlocker, second is secret_hash
                        // Extract secret_hash (h0) from event
                        if let Some(secret_hash) = data_array.get(1).and_then(|v| v.as_str()) {
                            println!("✅ Unlocked event detected!");
                            println!("   Secret hash: {}", secret_hash);
                            // In production, extract full secret from transaction calldata
                            return Ok(secret_hash.to_string());
                        }
                    }
                }
            }
        }

        last_block = current_block;
    }
}
