//! Minimal Monero stagenet integration demo.
//!
//! WARNING: This is a minimal adaptor-signature demo, NOT a production wallet integration.
//!
//! This module provides a simplified demonstration of:
//! - Transaction creation with adaptor signatures (simplified, not full CLSAG)
//! - Signature finalization (demo implementation)
//! - Transaction broadcasting (basic RPC calls)
//!
//! **What's NOT implemented** (required for production):
//! - Full CLSAG (Compact Linkable Spontaneous Anonymous Group signatures)
//! - Robust key image handling
//! - Change output management
//! - Multi-output transaction support
//! - Ring signature construction
//! - Proper transaction fee calculation
//!
//! Production swaps must use wallet-rpc/monero transaction tooling that creates,
//! signs, and broadcasts real CLSAG transactions. This module intentionally fails
//! closed for transaction finalization instead of returning fake transaction hex.

use anyhow::{Context, Result};
use curve25519_dalek::scalar::Scalar;
use serde_json::{json, Value};

/// Monero RPC client for stagenet.
pub struct MoneroRpcClient {
    rpc_url: String,
    client: reqwest::Client,
}

impl MoneroRpcClient {
    pub fn new(rpc_url: String) -> Self {
        Self {
            rpc_url,
            client: reqwest::Client::new(),
        }
    }

    /// Call Monero JSON-RPC method.
    async fn call(&self, method: &str, params: Value) -> Result<Value> {
        let payload = json!({
            "jsonrpc": "2.0",
            "id": "0",
            "method": method,
            "params": params,
        });

        let response = self
            .client
            .post(&self.rpc_url)
            .json(&payload)
            .send()
            .await
            .context("Failed to send Monero RPC request")?;

        let result: Value = response
            .json()
            .await
            .context("Failed to parse Monero RPC response")?;

        if let Some(error) = result.get("error") {
            anyhow::bail!("Monero RPC error: {}", error);
        }

        Ok(result.get("result").cloned().unwrap_or(result))
    }

    /// Get current block height.
    pub async fn get_height(&self) -> Result<u64> {
        let result = self.call("get_info", json!({})).await?;
        let height = result
            .get("height")
            .and_then(|v| v.as_u64())
            .context("Invalid height format")?;
        Ok(height)
    }

    /// Create a transfer transaction (minimal demo - NOT production wallet integration).
    ///
    /// ⚠️ This is a simplified demo implementation. For production use, integrate with
    /// a proper Monero wallet library that handles CLSAG, key images, change outputs, etc.
    pub async fn create_transfer(
        &self,
        destinations: Vec<(String, u64)>, // (address, amount)
        priority: Option<u64>,
    ) -> Result<Value> {
        let mut dests = Vec::new();
        for (address, amount) in destinations {
            dests.push(json!({
                "amount": amount,
                "address": address,
            }));
        }

        let params = json!({
            "destinations": dests,
            "priority": priority.unwrap_or(1),
            "ring_size": 11,
            "get_tx_key": true,
        });

        self.call("transfer", params).await
    }

    /// Submit a transaction to the network.
    pub async fn submit_transaction(&self, tx_hex: &str) -> Result<String> {
        let params = json!({
            "tx_as_hex": tx_hex,
        });

        let result = self.call("send_raw_transaction", params).await?;

        if let Some(tx_hash) = result.get("tx_hash_list") {
            if let Some(tx_list) = tx_hash.as_array() {
                if let Some(first_tx) = tx_list.first() {
                    if let Some(hash) = first_tx.as_str() {
                        return Ok(hash.to_string());
                    }
                }
            }
        }

        anyhow::bail!("Failed to extract transaction hash from response")
    }

    /// Get transaction details.
    pub async fn get_transaction(&self, tx_hash: &str) -> Result<Value> {
        let params = json!({
            "tx_hashes": [tx_hash],
        });

        self.call("get_transactions", params).await
    }
}

/// Finalize a Monero adaptor signature and create broadcastable transaction.
///
/// **⚠️ WARNING**: This is a minimal demo implementation, NOT a production wallet module.
/// It does not handle full CLSAG, key images, change outputs, or multi-output transactions.
pub struct MoneroTransactionBuilder {
    adaptor_sig: crate::adaptor::AdaptorSignature,
    partial_tx_data: Value,
}

impl MoneroTransactionBuilder {
    pub fn new(adaptor_sig: crate::adaptor::AdaptorSignature, partial_tx_data: Value) -> Self {
        Self {
            adaptor_sig,
            partial_tx_data,
        }
    }

    /// Finalize the transaction signature using the revealed secret scalar.
    ///
    /// This path is intentionally disabled for production safety. The previous
    /// implementation returned `"finalized_tx_hex_placeholder"`, which could be
    /// mistaken for a broadcastable transaction by downstream automation.
    pub fn finalize(&mut self, secret_scalar: &Scalar) -> Result<String> {
        let _ = (&self.adaptor_sig, &self.partial_tx_data, secret_scalar);
        anyhow::bail!(
            "Monero transaction finalization is not implemented in rust/src/monero_full.rs. Use wallet-rpc/Monero tooling to create and sign a real stagenet transaction; placeholder transaction hex is forbidden."
        )
    }
}
