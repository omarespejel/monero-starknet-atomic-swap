//! RPC-based relayer: wait for Monero confirmations, then reveal secret on Starknet.
//!
//! This is a deployable, trusted relayer path (Phase 1). It does NOT perform
//! on-chain Monero verification; it relies on Monero daemon RPC.

use anyhow::{anyhow, Context, Result};
use clap::Parser;
use reqwest::Client;
use serde_json::json;
use std::time::Duration;
use tokio::time::sleep;
use tracing::{info, warn};

use xmr_secret_gen::swap::{StarknetClient, StarknetManualClient};

#[derive(Parser)]
#[command(name = "relay_reveal")]
#[command(about = "Monero RPC relayer for Starknet reveal_secret")]
struct Args {
    /// Starknet RPC URL (default: Sepolia)
    #[arg(
        long,
        default_value = "https://api.zan.top/public/starknet-sepolia/rpc/v0_10"
    )]
    starknet_rpc: String,

    /// Starknet account address (hex, 0x...)
    #[arg(long)]
    account_address: String,

    /// Starknet account private key (hex, 0x...)
    #[arg(long)]
    private_key: String,

    /// AtomicLock class hash (hex, 0x...); required by client constructor
    #[arg(long)]
    atomic_lock_class_hash: String,

    /// Chain ID felt (hex). Default: SN_SEPOLIA
    #[arg(long, default_value = "0x534e5f5345504f4c4941")]
    chain_id: String,

    /// AtomicLock contract address (hex, 0x...)
    #[arg(long)]
    contract_address: String,

    /// Secret to reveal (32 bytes hex, with/without 0x)
    #[arg(long)]
    secret_hex: String,

    /// Monero daemon RPC URL (e.g., http://localhost:18081/json_rpc)
    #[arg(long, default_value = "http://localhost:18081/json_rpc")]
    monero_daemon_url: String,

    /// Monero txid to monitor (hex)
    #[arg(long)]
    monero_txid: String,

    /// Required confirmations before reveal
    #[arg(long, default_value_t = 10)]
    confirmations: u64,

    /// Poll interval (seconds)
    #[arg(long, default_value_t = 20)]
    poll_interval_secs: u64,
}

#[derive(Debug, Clone)]
struct TxInfo {
    block_height: u64,
    confirmations: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    let args = Args::parse();
    let secret = parse_secret(&args.secret_hex)?;

    let starknet = StarknetManualClient::new(
        &args.starknet_rpc,
        &args.account_address,
        &args.private_key,
        &args.atomic_lock_class_hash,
        &args.chain_id,
    )
    .context("Failed to initialize Starknet client")?;

    if starknet
        .is_secret_revealed(&args.contract_address)
        .await
        .unwrap_or(false)
    {
        info!(
            "Secret already revealed on contract {}, skipping.",
            args.contract_address
        );
        return Ok(());
    }

    info!(
        "Waiting for Monero confirmations: tx {}, required {}",
        args.monero_txid, args.confirmations
    );

    wait_for_confirmations(
        &args.monero_daemon_url,
        &args.monero_txid,
        args.confirmations,
        args.poll_interval_secs,
    )
    .await?;

    info!("Monero tx confirmed. Revealing secret on Starknet...");
    let tx_hash = starknet
        .reveal_secret(&args.contract_address, &secret)
        .await
        .context("Failed to submit reveal_secret")?;

    info!("reveal_secret submitted: {}", tx_hash);
    Ok(())
}

fn parse_secret(secret_hex: &str) -> Result<[u8; 32]> {
    let hex_str = secret_hex.strip_prefix("0x").unwrap_or(secret_hex);
    let bytes = hex::decode(hex_str).context("Invalid secret hex")?;
    if bytes.len() != 32 {
        return Err(anyhow!(
            "Secret must be 32 bytes (got {} bytes)",
            bytes.len()
        ));
    }
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    Ok(out)
}

async fn wait_for_confirmations(
    daemon_url: &str,
    txid: &str,
    min_confirmations: u64,
    poll_interval_secs: u64,
) -> Result<TxInfo> {
    loop {
        match get_tx_info(daemon_url, txid).await {
            Ok(Some(info)) => {
                if info.confirmations >= min_confirmations {
                    info!(
                        "Monero tx {} reached {} confirmations at height {}",
                        txid, info.confirmations, info.block_height
                    );
                    return Ok(info);
                }
                info!(
                    "Waiting for confirmations: {}/{} for tx {} (height {})",
                    info.confirmations, min_confirmations, txid, info.block_height
                );
            }
            Ok(None) => {
                warn!("Tx {} not yet in block; waiting...", txid);
            }
            Err(e) => {
                warn!("Monero RPC error for tx {}: {}", txid, e);
            }
        }

        sleep(Duration::from_secs(poll_interval_secs)).await;
    }
}

async fn get_tx_info(daemon_url: &str, txid: &str) -> Result<Option<TxInfo>> {
    let client = Client::new();
    let resp: serde_json::Value = client
        .post(daemon_url)
        .json(&json!({
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

    if let Some(error) = resp.get("error") {
        let error_msg = error
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown RPC error");
        return Err(anyhow!("Monero RPC error: {}", error_msg));
    }

    let txs = resp
        .get("result")
        .and_then(|r| r.get("txs"))
        .and_then(|t| t.as_array())
        .ok_or_else(|| anyhow!("Invalid response format from Monero daemon"))?;

    if txs.is_empty() {
        return Ok(None);
    }

    let tx = &txs[0];
    let block_height = tx.get("block_height").and_then(|h| h.as_u64());

    if let Some(height) = block_height {
        let current_height = get_current_block_height(daemon_url).await?;
        let confirmations = current_height.saturating_sub(height) + 1;
        Ok(Some(TxInfo {
            block_height: height,
            confirmations,
        }))
    } else {
        Ok(None)
    }
}

async fn get_current_block_height(daemon_url: &str) -> Result<u64> {
    let client = Client::new();
    let resp: serde_json::Value = client
        .post(daemon_url)
        .json(&json!({
            "jsonrpc": "2.0",
            "id": "0",
            "method": "get_block_count"
        }))
        .send()
        .await?
        .json()
        .await?;

    if let Some(error) = resp.get("error") {
        let error_msg = error
            .get("message")
            .and_then(|v| v.as_str())
            .unwrap_or("Unknown RPC error");
        return Err(anyhow!("Monero RPC error: {}", error_msg));
    }

    resp.get("result")
        .and_then(|r| r.get("count"))
        .and_then(|c| c.as_u64())
        .ok_or_else(|| anyhow!("Invalid response format from Monero daemon"))
}
