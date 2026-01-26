use anyhow::{anyhow, Context, Result};
use std::time::Duration;
use tracing::{info, warn};

use crate::monero::watcher::wait_for_confirmations;
use crate::registry::SwapRegistry;
use tokio::sync::RwLock;
use xmr_secret_gen::swap::{StarknetClient, StarknetManualClient};

pub struct RelayConfig {
    pub starknet_rpc: String,
    pub account_address: String,
    pub private_key: String,
    pub atomic_lock_class_hash: String,
    pub chain_id: String,
    pub contract_address: String,
    pub secret_hex: String,
    pub monero_txid: String,
    pub confirmations: u64,
    pub poll_interval_secs: u64,
    pub monero_daemon_url: String,
}

pub fn start_relayer_pool(
    monero_daemon_url: &str,
    registry: Option<std::sync::Arc<RwLock<SwapRegistry>>>,
) -> Result<Vec<tokio::task::JoinHandle<()>>> {
    let mut configs = Vec::new();

    if let Some(config) = RelayConfig::from_env(monero_daemon_url)? {
        configs.push(config);
    }

    if let Some(path) = std::env::var("RELAY_SWAPS_PATH").ok() {
        let relay_file = RelayFile::load(&path)?;
        configs.extend(relay_file.into_configs(monero_daemon_url)?);
    }

    if configs.is_empty() {
        info!("Relayer disabled (set RELAY_CONTRACT_ADDRESS or RELAY_SWAPS_PATH).");
        return Ok(Vec::new());
    }

    let handles = configs
        .into_iter()
        .map(|config| {
            let registry_clone = registry.clone();
            tokio::spawn(async move {
                if let Err(e) = run_relayer(config, registry_clone).await {
                    warn!("Relayer task failed: {}", e);
                }
            })
        })
        .collect();

    Ok(handles)
}

impl RelayConfig {
    pub fn from_env(monero_daemon_url: &str) -> Result<Option<Self>> {
        let contract_address = match std::env::var("RELAY_CONTRACT_ADDRESS") {
            Ok(value) if !value.trim().is_empty() => value,
            _ => return Ok(None),
        };

        let account_address = required_env("RELAY_ACCOUNT_ADDRESS")?;
        let private_key = required_env("RELAY_PRIVATE_KEY")?;
        let atomic_lock_class_hash = required_env("RELAY_ATOMIC_LOCK_CLASS_HASH")?;
        let secret_hex = required_env("RELAY_SECRET_HEX")?;
        let monero_txid = required_env("RELAY_MONERO_TXID")?;

        let chain_id = std::env::var("RELAY_CHAIN_ID")
            .unwrap_or_else(|_| "0x534e5f5345504f4c4941".to_string());
        let confirmations = std::env::var("RELAY_CONFIRMATIONS")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(10);
        let poll_interval_secs = std::env::var("RELAY_POLL_INTERVAL_SECS")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .unwrap_or(20);
        let starknet_rpc = std::env::var("RELAY_STARKNET_RPC_URL")
            .or_else(|_| std::env::var("STARKNET_RPC_URL"))
            .unwrap_or_else(|_| "https://api.zan.top/public/starknet-sepolia".to_string());

        Ok(Some(Self {
            starknet_rpc,
            account_address,
            private_key,
            atomic_lock_class_hash,
            chain_id,
            contract_address,
            secret_hex,
            monero_txid,
            confirmations,
            poll_interval_secs,
            monero_daemon_url: monero_daemon_url.to_string(),
        }))
    }
}

async fn run_relayer(
    config: RelayConfig,
    registry: Option<std::sync::Arc<RwLock<SwapRegistry>>>,
) -> Result<()> {
    let secret = parse_secret(&config.secret_hex)?;

    let starknet = StarknetManualClient::new(
        &config.starknet_rpc,
        &config.account_address,
        &config.private_key,
        &config.atomic_lock_class_hash,
        &config.chain_id,
    )
    .context("Failed to initialize Starknet client")?;

    match starknet.is_secret_revealed(&config.contract_address).await {
        Ok(true) => {
            info!(
                "Secret already revealed on contract {}, skipping.",
                config.contract_address
            );
            return Ok(());
        }
        Ok(false) => {}
        Err(e) => {
            warn!("Failed to query is_secret_revealed: {}", e);
        }
    }

    info!(
        "Relayer waiting for Monero confirmations: tx {}, required {}",
        config.monero_txid, config.confirmations
    );

    wait_for_confirmations(
        &config.monero_daemon_url,
        &config.monero_txid,
        config.confirmations,
        Duration::from_secs(config.poll_interval_secs),
    )
    .await?;

    info!("Monero confirmed. Revealing secret on Starknet...");
    let tx_hash = starknet
        .reveal_secret(&config.contract_address, &secret)
        .await
        .context("Failed to submit reveal_secret")?;

    info!("reveal_secret submitted: {}", tx_hash);

    if let Some(registry) = registry {
        let mut registry = registry.write().await;
        registry.record_relayer_submission(&config.contract_address, &tx_hash);
        let _ = registry.save();
    }
    Ok(())
}

fn required_env(name: &str) -> Result<String> {
    std::env::var(name).with_context(|| format!("Missing required env var {}", name))
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_secret_rejects_wrong_length() {
        let err = parse_secret("0x1234").unwrap_err();
        assert!(err.to_string().contains("32 bytes"));
    }

    #[test]
    fn relay_file_defaults_applied() {
        let file = RelayFile {
            defaults: Some(RelayDefaults {
                starknet_rpc: Some("https://rpc".to_string()),
                account_address: Some("0x1".to_string()),
                private_key: Some("0x2".to_string()),
                atomic_lock_class_hash: Some("0x3".to_string()),
                chain_id: Some("0x4".to_string()),
                confirmations: Some(12),
                poll_interval_secs: Some(30),
            }),
            swaps: vec![RelaySwap {
                contract_address: "0xabc".to_string(),
                secret_hex: "0x".to_string() + &"11".repeat(32),
                monero_txid: "txid".to_string(),
                confirmations: None,
                poll_interval_secs: None,
                starknet_rpc: None,
                account_address: None,
                private_key: None,
                atomic_lock_class_hash: None,
                chain_id: None,
            }],
        };

        let configs = file.into_configs("http://monero").unwrap();
        assert_eq!(configs.len(), 1);
        assert_eq!(configs[0].confirmations, 12);
        assert_eq!(configs[0].poll_interval_secs, 30);
        assert_eq!(configs[0].starknet_rpc, "https://rpc");
    }
}

#[derive(Debug, Clone, serde::Deserialize)]
struct RelayFile {
    defaults: Option<RelayDefaults>,
    swaps: Vec<RelaySwap>,
}

#[derive(Debug, Clone, serde::Deserialize)]
struct RelayDefaults {
    starknet_rpc: Option<String>,
    account_address: Option<String>,
    private_key: Option<String>,
    atomic_lock_class_hash: Option<String>,
    chain_id: Option<String>,
    confirmations: Option<u64>,
    poll_interval_secs: Option<u64>,
}

#[derive(Debug, Clone, serde::Deserialize)]
struct RelaySwap {
    contract_address: String,
    secret_hex: String,
    monero_txid: String,
    confirmations: Option<u64>,
    poll_interval_secs: Option<u64>,
    starknet_rpc: Option<String>,
    account_address: Option<String>,
    private_key: Option<String>,
    atomic_lock_class_hash: Option<String>,
    chain_id: Option<String>,
}

impl RelayFile {
    fn load(path: &str) -> Result<Self> {
        let contents = std::fs::read_to_string(path)
            .with_context(|| format!("Failed to read relay file {}", path))?;
        let file = serde_json::from_str(&contents)
            .with_context(|| format!("Failed to parse relay file {}", path))?;
        Ok(file)
    }

    fn into_configs(self, monero_daemon_url: &str) -> Result<Vec<RelayConfig>> {
        let mut out = Vec::new();
        let defaults = self.defaults.unwrap_or(RelayDefaults {
            starknet_rpc: None,
            account_address: None,
            private_key: None,
            atomic_lock_class_hash: None,
            chain_id: None,
            confirmations: None,
            poll_interval_secs: None,
        });

        for swap in self.swaps {
            let config = RelayConfig {
                starknet_rpc: swap
                    .starknet_rpc
                    .or_else(|| defaults.starknet_rpc.clone())
                    .unwrap_or_else(|| "https://api.zan.top/public/starknet-sepolia".to_string()),
                account_address: swap
                    .account_address
                    .or_else(|| defaults.account_address.clone())
                    .ok_or_else(|| anyhow!("Missing account_address for relay swap"))?,
                private_key: swap
                    .private_key
                    .or_else(|| defaults.private_key.clone())
                    .ok_or_else(|| anyhow!("Missing private_key for relay swap"))?,
                atomic_lock_class_hash: swap
                    .atomic_lock_class_hash
                    .or_else(|| defaults.atomic_lock_class_hash.clone())
                    .ok_or_else(|| anyhow!("Missing atomic_lock_class_hash for relay swap"))?,
                chain_id: swap
                    .chain_id
                    .or_else(|| defaults.chain_id.clone())
                    .unwrap_or_else(|| "0x534e5f5345504f4c4941".to_string()),
                contract_address: swap.contract_address,
                secret_hex: swap.secret_hex,
                monero_txid: swap.monero_txid,
                confirmations: swap.confirmations.or(defaults.confirmations).unwrap_or(10),
                poll_interval_secs: swap.poll_interval_secs.or(defaults.poll_interval_secs).unwrap_or(20),
                monero_daemon_url: monero_daemon_url.to_string(),
            };
            out.push(config);
        }

        Ok(out)
    }
}
