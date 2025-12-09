//! Minimal Monero stagenet integration helper
//! Based on COMIT Network's production-tested approach
//! Uses jsonrpc_client for proper JSON-RPC protocol handling

//! Minimal Monero stagenet integration helper
//! Based on COMIT Network's production-tested approach
//! Uses reqwest directly for JSON-RPC (jsonrpc_client API may differ)

use anyhow::{Context, Result};
use reqwest::Client;
use serde_json::{json, Value};
use std::time::Duration;
use tokio::time::sleep;

/// Monero stagenet test helper
pub struct MoneroStagenet {
    pub rpc_url: String,
    pub http_client: Client,
    pub wallet_name: String,
}

impl MoneroStagenet {
    /// Connect to public stagenet node (no local setup needed!)
    /// Tries multiple public stagenet nodes as fallbacks
    pub async fn connect_public() -> Result<Self> {
        // Try multiple public stagenet nodes (fallback if one is down)
        let rpc_urls = vec![
            "http://stagenet.melo.tools:38081/json_rpc",
            "http://stagenet.community.rino.io:38081/json_rpc",
            "http://localhost:38081/json_rpc", // Local fallback
        ];

        let http_client = Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .context("Failed to create HTTP client")?;

        // Try each URL until one works
        for rpc_url in &rpc_urls {
            match Self::get_height_internal(&http_client, rpc_url).await {
                Ok(height) => {
                    println!("✅ Connected to Monero stagenet at {}! Height: {}", rpc_url, height);
                    return Ok(Self {
                        rpc_url: rpc_url.to_string(),
                        http_client,
                        wallet_name: "swap-test-wallet".to_string(),
                    });
                }
                Err(e) => {
                    println!("⚠️  Failed to connect to {}: {}", rpc_url, e);
                    continue;
                }
            }
        }

        Err(anyhow::anyhow!(
            "Failed to connect to any Monero stagenet node. Tried: {:?}",
            rpc_urls
        ))
    }

    /// Internal helper to get blockchain height via JSON-RPC
    async fn get_height_internal(client: &Client, rpc_url: &str) -> Result<u64> {
        let response = client
            .post(rpc_url)
            .json(&json!({
                "jsonrpc": "2.0",
                "id": "0",
                "method": "get_block_count",
                "params": {}
            }))
            .send()
            .await
            .context("Failed to connect to Monero stagenet node")?;

        let json: Value = response
            .json()
            .await
            .context("Failed to parse JSON response")?;

        // Monero returns {"result": {"count": <height>}}
        let height = json["result"]["count"]
            .as_u64()
            .context("Invalid response format - missing count")?;

        Ok(height)
    }

    /// Wait for N confirmations (essential for atomic swap timing)
    pub async fn wait_confirmations(&self, _tx_hash: String, confirmations: u64) -> Result<()> {
        let start_height = self.height().await?;
        let target = start_height + confirmations;

        println!(
            "⏳ Waiting for {} confirmations (from height {} to {})...",
            confirmations, start_height, target
        );

        while self.height().await? < target {
            sleep(Duration::from_secs(12)).await; // ~2min per block
        }

        Ok(())
    }

    /// Get current blockchain height
    pub async fn height(&self) -> Result<u64> {
        Self::get_height_internal(&self.http_client, &self.rpc_url).await
    }
}

