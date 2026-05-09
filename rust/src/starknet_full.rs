//! Full Starknet integration using direct JSON-RPC calls.
//!
//! This module provides complete integration for:
//! - Contract deployment
//! - Event watching
//! - Contract function calls
//!
//! Uses direct JSON-RPC calls for maximum compatibility and stability.

use anyhow::{Context, Result};
use serde_json::{json, Value};

/// Starknet JSON-RPC client with account support.
#[allow(dead_code)]
pub struct StarknetAccount {
    rpc_url: String,
    account_address: String,
    private_key: String,
    client: reqwest::Client,
}

impl StarknetAccount {
    /// Create a new Starknet account client.
    pub fn new(rpc_url: String, account_address: String, private_key: String) -> Self {
        Self {
            rpc_url,
            account_address,
            private_key,
            client: reqwest::Client::new(),
        }
    }

    /// Call Starknet JSON-RPC method.
    #[allow(dead_code)]
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

    /// Deploy a contract (simplified - requires full implementation with account signing).
    pub async fn deploy_contract(
        &self,
        contract_class: &Value, // Sierra/CASM contract class
        constructor_calldata: Vec<String>,
    ) -> Result<String> {
        let _ = (contract_class, constructor_calldata);
        anyhow::bail!(
            "Rust Starknet deployment is not implemented safely in starknet_full.rs. Use scripts/deploy.ts or tools/generate_deploy_calldata.py with a signed account; returning a fake 0x0 address is forbidden."
        )
    }

    /// Call a contract function (verify_and_unlock).
    pub async fn verify_and_unlock(
        &self,
        contract_address: &str,
        secret_bytes: &[u8],
    ) -> Result<String> {
        // Convert secret to ByteArray format
        let secret_hex = hex::encode(secret_bytes);

        // Create calldata for verify_and_unlock(secret: ByteArray)
        // ByteArray format: [length, ...bytes as felts]
        let mut calldata = Vec::new();
        calldata.push(format!("0x{:x}", secret_bytes.len()));

        // Add secret bytes (simplified - proper ByteArray serialization needed)
        for chunk in secret_bytes.chunks(31) {
            let chunk_hex = hex::encode(chunk);
            calldata.push(format!("0x{}", chunk_hex));
        }

        let _ = (contract_address, secret_hex, calldata);
        anyhow::bail!(
            "Rust Starknet signed invoke is not implemented safely in starknet_full.rs. Use the TypeScript/starknet.js path for reveal transactions; returning a fake 0x0 transaction hash is forbidden."
        )
    }

    /// Watch for Unlocked events from a contract.
    pub async fn watch_unlocked_events(
        &self,
        contract_address: &str,
        poll_interval_secs: u64,
    ) -> Result<String> {
        let _ = (contract_address, poll_interval_secs);
        anyhow::bail!(
            "Rust event watching in starknet_full.rs is not production-safe yet because ABI event selectors and pagination are not implemented. Use Starknet RPC tooling or explorer queries until this module decodes events from the compiled ABI."
        )
    }

    /// Get current block number.
    #[allow(dead_code)]
    async fn get_block_number(&self) -> Result<u64> {
        let result = self.call("starknet_blockNumber", json!([])).await?;
        let block_num_str = result.as_str().context("Invalid block number format")?;

        let block_num = if let Some(hex_str) = block_num_str.strip_prefix("0x") {
            u64::from_str_radix(hex_str, 16).context("Failed to parse block number")?
        } else {
            block_num_str
                .parse()
                .context("Failed to parse block number")?
        };

        Ok(block_num)
    }
}

/// Helper to create AtomicLock contract deployment calldata.
pub fn create_atomic_lock_calldata(
    hash_words: [u32; 8],
    lock_until: u64,
    token: &str,
    amount_low: u128,
    amount_high: u128,
    adaptor_point_x: &[String; 4],
    adaptor_point_y: &[String; 4],
    dleq: (&str, &str),
    fake_glv_hint: &[String; 10],
) -> Vec<String> {
    let mut calldata = Vec::new();

    // Hash words (8 u32)
    for word in hash_words {
        calldata.push(format!("0x{:x}", word));
    }

    // Lock until (u64)
    calldata.push(format!("0x{:x}", lock_until));

    // Token address
    calldata.push(token.to_string());

    // Amount (u256: low, high)
    calldata.push(format!("0x{:x}", amount_low));
    calldata.push(format!("0x{:x}", amount_high));

    // Adaptor point x (4 felts)
    for x in adaptor_point_x {
        calldata.push(x.clone());
    }

    // Adaptor point y (4 felts)
    for y in adaptor_point_y {
        calldata.push(y.clone());
    }

    // DLEQ (2 felts)
    calldata.push(dleq.0.to_string());
    calldata.push(dleq.1.to_string());

    // Fake GLV hint (10 felts)
    for hint in fake_glv_hint {
        calldata.push(hint.clone());
    }

    calldata
}
