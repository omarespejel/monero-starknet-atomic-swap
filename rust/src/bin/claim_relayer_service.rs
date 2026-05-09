//! Multi-lock claim relayer service.
//!
//! `claim_revealed_secrets` is the focused one-lock tool used for rehearsals.
//! This binary is the long-running service wrapper: it reloads a JSON inventory,
//! runs each enabled lock with its own cursor and partial-key environment
//! variable, and keeps later locks moving even if one lock hits an RPC error.

use anyhow::{anyhow, Context, Result};
use async_trait::async_trait;
use clap::Parser;
use monero::Network;
use serde::Deserialize;
use std::collections::BTreeSet;
use std::env;
use std::path::{Path, PathBuf};
use std::time::Duration;
use tokio::time::sleep;
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;
use zeroize::{Zeroize, Zeroizing};

use xmr_secret_gen::starknet::StarknetClient;
use xmr_secret_gen::swap::relayer::{
    MoneroClaimConfig, MoneroSecretClaimant, MoneroWalletSecretClaimant, RelayerConfig,
    RetryPolicy, SecretReveal, SecretRevealRelayer,
};

const DEFAULT_STARKNET_RPC: &str =
    "https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_10/cf52O0RwFy1mEB0uoYsel";

#[derive(Parser, Debug)]
#[command(name = "claim_relayer_service")]
#[command(about = "Long-running multi-lock Starknet-to-Monero claim relayer")]
struct Args {
    /// JSON inventory describing AtomicLock contracts to watch.
    #[arg(long)]
    config: PathBuf,

    /// Decode and cursor events without touching Monero wallet-rpc.
    #[arg(long)]
    dry_run: bool,

    /// Run one pass over enabled locks and exit.
    #[arg(long)]
    once: bool,

    /// Exit on the first lock error. Default keeps processing later locks.
    #[arg(long)]
    fail_fast: bool,

    /// Override the config/default poll interval.
    #[arg(long)]
    poll_interval_secs: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
struct ServiceConfig {
    #[serde(default)]
    defaults: ServiceDefaults,
    locks: Vec<LockConfig>,
}

#[derive(Debug, Clone, Default, Deserialize)]
struct ServiceDefaults {
    starknet_rpc: Option<String>,
    wallet_rpc_url: Option<String>,
    daemon_rpc_url: Option<String>,
    wallet_dir: Option<PathBuf>,
    monero_network: Option<String>,
    claim_destination: Option<String>,
    cursor_dir: Option<PathBuf>,
    confirmation_depth: Option<u64>,
    reorg_validation_depth: Option<u64>,
    max_blocks_per_batch: Option<u64>,
    retry_attempts: Option<u32>,
    retry_backoff_secs: Option<u64>,
    poll_interval_secs: Option<u64>,
}

#[derive(Debug, Clone, Deserialize)]
struct LockConfig {
    id: String,
    contract_address: String,
    start_block: u64,
    #[serde(default)]
    enabled: Option<bool>,
    #[serde(default)]
    cursor_path: Option<PathBuf>,
    #[serde(default)]
    partial_spend_key_env: Option<String>,
    #[serde(default)]
    restore_height: Option<u64>,
    #[serde(default)]
    starknet_rpc: Option<String>,
    #[serde(default)]
    wallet_rpc_url: Option<String>,
    #[serde(default)]
    daemon_rpc_url: Option<String>,
    #[serde(default)]
    wallet_dir: Option<PathBuf>,
    #[serde(default)]
    monero_network: Option<String>,
    #[serde(default)]
    claim_destination: Option<String>,
    #[serde(default)]
    confirmation_depth: Option<u64>,
    #[serde(default)]
    reorg_validation_depth: Option<u64>,
    #[serde(default)]
    max_blocks_per_batch: Option<u64>,
    #[serde(default)]
    retry_attempts: Option<u32>,
    #[serde(default)]
    retry_backoff_secs: Option<u64>,
}

#[derive(Debug, Default)]
struct ServicePassStats {
    enabled_locks: usize,
    succeeded_locks: usize,
    failed_locks: usize,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let args = Args::parse();
    if args.once {
        let config = load_config(&args.config)?;
        validate_config(&config)?;
        let stats = run_service_pass(&args, &config).await?;
        if stats.failed_locks > 0 {
            anyhow::bail!(
                "{} lock(s) failed in one-shot service pass",
                stats.failed_locks
            );
        }
        return Ok(());
    }

    loop {
        match load_config(&args.config).and_then(|config| {
            validate_config(&config)?;
            Ok(config)
        }) {
            Ok(config) => {
                if let Err(err) = run_service_pass(&args, &config).await {
                    error!(error = %err, "claim relayer service pass failed");
                    if args.fail_fast {
                        return Err(err);
                    }
                }

                sleep(Duration::from_secs(poll_interval_secs(&args, &config))).await;
            }
            Err(err) => {
                error!(error = %err, "failed to load claim relayer config");
                sleep(Duration::from_secs(args.poll_interval_secs.unwrap_or(30))).await;
            }
        }
    }
}

fn load_config(path: &Path) -> Result<ServiceConfig> {
    let raw = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read relayer config {}", path.display()))?;
    serde_json::from_str(&raw)
        .with_context(|| format!("Failed to parse relayer config {}", path.display()))
}

fn validate_config(config: &ServiceConfig) -> Result<()> {
    let mut ids = BTreeSet::new();
    for lock in &config.locks {
        if lock.id.trim().is_empty() {
            anyhow::bail!("Lock id cannot be empty");
        }
        if !ids.insert(lock.id.clone()) {
            anyhow::bail!("Duplicate lock id in relayer config: {}", lock.id);
        }
        if lock.enabled() && lock.start_block == 0 {
            warn!(
                lock_id = lock.id,
                "lock starts at block 0; use the deployment block in production"
            );
        }
    }

    if config.locks.iter().all(|lock| !lock.enabled()) {
        anyhow::bail!("Relayer config has no enabled locks");
    }

    Ok(())
}

async fn run_service_pass(args: &Args, config: &ServiceConfig) -> Result<ServicePassStats> {
    let mut stats = ServicePassStats::default();
    for lock in config.locks.iter().filter(|lock| lock.enabled()) {
        stats.enabled_locks += 1;
        match run_lock_once(args, config, lock).await {
            Ok(()) => stats.succeeded_locks += 1,
            Err(err) => {
                stats.failed_locks += 1;
                error!(
                    lock_id = lock.id,
                    contract_address = lock.contract_address,
                    error = %err,
                    "claim relayer lock pass failed"
                );
                if args.fail_fast {
                    return Err(err);
                }
            }
        }
    }

    info!(
        enabled_locks = stats.enabled_locks,
        succeeded_locks = stats.succeeded_locks,
        failed_locks = stats.failed_locks,
        "claim relayer service pass complete"
    );
    Ok(stats)
}

async fn run_lock_once(args: &Args, config: &ServiceConfig, lock: &LockConfig) -> Result<()> {
    let source = StarknetClient::new(lock_string(
        &lock.starknet_rpc,
        &config.defaults.starknet_rpc,
        DEFAULT_STARKNET_RPC,
    ));
    let relayer = SecretRevealRelayer::new(relayer_config(config, lock)?);

    if args.dry_run {
        let stats = relayer.run_once(&source, &DryRunClaimant).await?;
        log_lock_stats(lock, &stats);
        return Ok(());
    }

    let claimant = MoneroWalletSecretClaimant::new(monero_claim_config(config, lock)?);
    let stats = relayer.run_once(&source, &claimant).await?;
    log_lock_stats(lock, &stats);
    Ok(())
}

fn log_lock_stats(lock: &LockConfig, stats: &xmr_secret_gen::swap::relayer::RelayerRunStats) {
    info!(
        lock_id = lock.id,
        contract_address = lock.contract_address,
        latest_block = stats.latest_block,
        safe_tip = ?stats.safe_tip,
        from_block = stats.from_block,
        to_block = ?stats.to_block,
        events_seen = stats.events_seen,
        reveals_claimed = stats.reveals_claimed,
        events_skipped = stats.events_skipped,
        "claim relayer lock pass complete"
    );
}

fn relayer_config(config: &ServiceConfig, lock: &LockConfig) -> Result<RelayerConfig> {
    let mut relayer = RelayerConfig::new(
        lock.contract_address.clone(),
        cursor_path(&config.defaults, lock)?,
        lock.start_block,
    );
    relayer.confirmation_depth = lock
        .confirmation_depth
        .or(config.defaults.confirmation_depth)
        .unwrap_or(relayer.confirmation_depth);
    relayer.reorg_validation_depth = lock
        .reorg_validation_depth
        .or(config.defaults.reorg_validation_depth)
        .unwrap_or(relayer.reorg_validation_depth);
    relayer.max_blocks_per_batch = lock
        .max_blocks_per_batch
        .or(config.defaults.max_blocks_per_batch)
        .unwrap_or(relayer.max_blocks_per_batch);
    relayer.retry = RetryPolicy {
        max_attempts: lock
            .retry_attempts
            .or(config.defaults.retry_attempts)
            .unwrap_or(relayer.retry.max_attempts),
        backoff_secs: lock
            .retry_backoff_secs
            .or(config.defaults.retry_backoff_secs)
            .unwrap_or(relayer.retry.backoff_secs),
    };
    Ok(relayer)
}

fn monero_claim_config(config: &ServiceConfig, lock: &LockConfig) -> Result<MoneroClaimConfig> {
    let env_name = lock
        .partial_spend_key_env
        .as_deref()
        .ok_or_else(|| anyhow!("Lock {} missing partial_spend_key_env", lock.id))?;
    let partial_spend_key = env::var(env_name)
        .with_context(|| format!("Missing partial key environment variable {}", env_name))?;

    let wallet_dir = lock_path(&lock.wallet_dir, &config.defaults.wallet_dir)
        .ok_or_else(|| anyhow!("Lock {} missing wallet_dir/defaults.wallet_dir", lock.id))?;
    if !wallet_dir.is_dir() {
        anyhow::bail!(
            "Wallet dir {} is not a local directory. Run inside the Monero VM.",
            wallet_dir.display()
        );
    }

    Ok(MoneroClaimConfig {
        wallet_rpc_url: required_string(
            &lock.wallet_rpc_url,
            &config.defaults.wallet_rpc_url,
            "wallet_rpc_url",
            &lock.id,
        )?,
        daemon_rpc_url: required_string(
            &lock.daemon_rpc_url,
            &config.defaults.daemon_rpc_url,
            "daemon_rpc_url",
            &lock.id,
        )?,
        wallet_dir: wallet_dir.to_string_lossy().into_owned(),
        partial_spend_key: Zeroizing::new(parse_secret_key(&partial_spend_key)?),
        claim_destination: required_string(
            &lock.claim_destination,
            &config.defaults.claim_destination,
            "claim_destination",
            &lock.id,
        )?,
        restore_height: lock
            .restore_height
            .ok_or_else(|| anyhow!("Lock {} missing restore_height", lock.id))?,
        network: parse_network(&lock_string(
            &lock.monero_network,
            &config.defaults.monero_network,
            "stagenet",
        ))?,
    })
}

fn cursor_path(defaults: &ServiceDefaults, lock: &LockConfig) -> Result<PathBuf> {
    if let Some(path) = &lock.cursor_path {
        return Ok(path.clone());
    }

    let cursor_dir = defaults
        .cursor_dir
        .clone()
        .unwrap_or_else(|| PathBuf::from(".relayer"));
    Ok(cursor_dir.join(format!("{}.json", sanitize_id(&lock.id))))
}

fn poll_interval_secs(args: &Args, config: &ServiceConfig) -> u64 {
    args.poll_interval_secs
        .or(config.defaults.poll_interval_secs)
        .unwrap_or(30)
}

fn required_string(
    lock_value: &Option<String>,
    default_value: &Option<String>,
    field: &str,
    lock_id: &str,
) -> Result<String> {
    lock_value
        .clone()
        .or_else(|| default_value.clone())
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| anyhow!("Lock {} missing {}", lock_id, field))
}

fn lock_string(
    lock_value: &Option<String>,
    default_value: &Option<String>,
    fallback: &str,
) -> String {
    lock_value
        .clone()
        .or_else(|| default_value.clone())
        .filter(|value| !value.trim().is_empty())
        .unwrap_or_else(|| fallback.to_string())
}

fn lock_path(lock_value: &Option<PathBuf>, default_value: &Option<PathBuf>) -> Option<PathBuf> {
    lock_value.clone().or_else(|| default_value.clone())
}

fn parse_secret_key(secret_hex: &str) -> Result<[u8; 32]> {
    let hex_str = secret_hex.strip_prefix("0x").unwrap_or(secret_hex);
    let mut bytes = hex::decode(hex_str).context("Invalid partial spend key hex")?;
    if bytes.len() != 32 {
        bytes.zeroize();
        return Err(anyhow!(
            "Partial spend key must be 32 bytes, got {} bytes",
            bytes.len()
        ));
    }
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    bytes.zeroize();
    Ok(out)
}

fn parse_network(network: &str) -> Result<Network> {
    match network.trim().to_ascii_lowercase().as_str() {
        "mainnet" | "main" => Ok(Network::Mainnet),
        "stagenet" | "stage" => Ok(Network::Stagenet),
        "testnet" | "test" => Ok(Network::Testnet),
        value => Err(anyhow!("Unsupported Monero network: {}", value)),
    }
}

fn sanitize_id(input: &str) -> String {
    input
        .chars()
        .map(|ch| {
            if ch.is_ascii_alphanumeric() || ch == '_' || ch == '-' {
                ch
            } else {
                '_'
            }
        })
        .collect()
}

impl LockConfig {
    fn enabled(&self) -> bool {
        self.enabled.unwrap_or(true)
    }
}

struct DryRunClaimant;

#[async_trait]
impl MoneroSecretClaimant for DryRunClaimant {
    async fn claim_revealed_secret(&self, reveal: &SecretReveal) -> Result<String> {
        info!(
            event_id = reveal.event_id,
            tx_hash = reveal.tx_hash,
            block_number = reveal.block_number,
            "dry-run Monero claim"
        );
        Ok("dry-run".to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_config() -> ServiceConfig {
        serde_json::from_str(
            r#"{
              "defaults": {
                "cursor_dir": "/var/lib/atomic-swap/cursors",
                "wallet_rpc_url": "http://127.0.0.1:38091/json_rpc",
                "daemon_rpc_url": "http://node2.monerodevs.org:38089/json_rpc",
                "wallet_dir": "/tmp",
                "claim_destination": "54SCqiAL4qNU3c6RNXFfz16c3EpS8HJehQHCRQXuvJZ3E3UJ5BcneuY6RKcFLUMQZagWvWXDT8r6MCnEotEK4EgKHfP9j43"
              },
              "locks": [{
                "id": "sepolia:test-lock",
                "contract_address": "0xabc",
                "start_block": 9560010,
                "restore_height": 2115270,
                "partial_spend_key_env": "RELAYER_TEST_PARTIAL"
              }]
            }"#,
        )
        .unwrap()
    }

    #[test]
    fn derives_cursor_path_from_sanitized_lock_id() {
        let config = sample_config();
        let path = cursor_path(&config.defaults, &config.locks[0]).unwrap();
        assert_eq!(
            path,
            PathBuf::from("/var/lib/atomic-swap/cursors/sepolia_test-lock.json")
        );
    }

    #[test]
    fn rejects_duplicate_lock_ids() {
        let mut config = sample_config();
        config.locks.push(config.locks[0].clone());
        let err = validate_config(&config).unwrap_err();
        assert!(err.to_string().contains("Duplicate lock id"));
    }

    #[test]
    fn parses_network_aliases() {
        assert_eq!(parse_network("stage").unwrap(), Network::Stagenet);
        assert_eq!(parse_network("mainnet").unwrap(), Network::Mainnet);
        assert!(parse_network("sepolia").is_err());
    }
}
