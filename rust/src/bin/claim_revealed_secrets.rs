//! Claim-side Starknet-to-Monero relayer loop.
//!
//! Watches finalized-enough AtomicLock `SecretRevealed` events, extracts the
//! public secret from the Starknet transaction calldata, recovers the Monero
//! spend key with the configured local partial key, and sweeps funds with
//! monero-wallet-rpc.

use anyhow::{anyhow, Context, Result};
use async_trait::async_trait;
use clap::Parser;
use monero::Network;
use std::path::PathBuf;
use std::time::Duration;
use tokio::time::sleep;
use tracing::info;
use zeroize::{Zeroize, Zeroizing};

use xmr_secret_gen::starknet::StarknetClient;
use xmr_secret_gen::swap::relayer::{
    MoneroClaimConfig, MoneroSecretClaimant, MoneroWalletSecretClaimant, RelayerConfig,
    RetryPolicy, SecretReveal, SecretRevealRelayer,
};

#[derive(Parser, Debug)]
#[command(name = "claim_revealed_secrets")]
#[command(about = "Durable Starknet SecretRevealed to Monero sweep relayer")]
struct Args {
    /// Starknet RPC URL.
    #[arg(
        long,
        default_value = "https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_10/cf52O0RwFy1mEB0uoYsel"
    )]
    starknet_rpc: String,

    /// AtomicLock contract address to watch.
    #[arg(long)]
    contract_address: String,

    /// Cursor JSON path.
    #[arg(long, default_value = ".relayer/claim_cursor.json")]
    cursor_path: PathBuf,

    /// First Starknet block to scan. Set this to the deployment block.
    #[arg(long)]
    start_block: u64,

    /// Starknet confirmations to wait before processing events.
    #[arg(long, default_value_t = 6)]
    confirmation_depth: u64,

    /// Number of retained finalized block hashes to re-check for reorgs.
    #[arg(long, default_value_t = 64)]
    reorg_validation_depth: u64,

    /// Maximum block span per event page.
    #[arg(long, default_value_t = 100)]
    max_blocks_per_batch: u64,

    /// Retry attempts for Starknet and Monero RPC calls.
    #[arg(long, default_value_t = 5)]
    retry_attempts: u32,

    /// Retry backoff in seconds.
    #[arg(long, default_value_t = 5)]
    retry_backoff_secs: u64,

    /// Poll interval in seconds when running continuously.
    #[arg(long, default_value_t = 30)]
    poll_interval_secs: u64,

    /// Run one polling pass and exit.
    #[arg(long)]
    once: bool,

    /// Decode and cursor events without touching Monero wallet-rpc.
    #[arg(long)]
    dry_run: bool,

    /// Monero wallet-rpc JSON-RPC URL. Run this binary inside the Monero VM.
    #[arg(long, default_value = "http://127.0.0.1:38090/json_rpc")]
    wallet_rpc_url: String,

    /// Monero daemon JSON-RPC URL.
    #[arg(long, default_value = "http://127.0.0.1:38081/json_rpc")]
    daemon_rpc_url: String,

    /// Local wallet directory on the same machine as wallet-rpc.
    #[arg(long)]
    wallet_dir: Option<String>,

    /// Monero network: mainnet, stagenet, or testnet.
    #[arg(long, default_value = "stagenet")]
    monero_network: String,

    /// Our local Monero partial spend key share as 32-byte hex.
    #[arg(long)]
    partial_spend_key_hex: Option<String>,

    /// Destination address for swept Monero funds.
    #[arg(long)]
    claim_destination: Option<String>,

    /// Monero restore height for the swap output wallet.
    #[arg(long)]
    restore_height: Option<u64>,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    let args = Args::parse();
    let source = StarknetClient::new(args.starknet_rpc.clone());
    let relayer = SecretRevealRelayer::new(relayer_config(&args));

    if args.dry_run {
        run_loop(&args, &relayer, &source, &DryRunClaimant).await
    } else {
        let claimant = MoneroWalletSecretClaimant::new(monero_claim_config(&args)?);
        run_loop(&args, &relayer, &source, &claimant).await
    }
}

async fn run_loop<C>(
    args: &Args,
    relayer: &SecretRevealRelayer,
    source: &StarknetClient,
    claimant: &C,
) -> Result<()>
where
    C: MoneroSecretClaimant,
{
    loop {
        let stats = relayer.run_once(source, claimant).await?;
        info!(
            latest_block = stats.latest_block,
            safe_tip = ?stats.safe_tip,
            from_block = stats.from_block,
            to_block = ?stats.to_block,
            events_seen = stats.events_seen,
            reveals_claimed = stats.reveals_claimed,
            events_skipped = stats.events_skipped,
            "relayer pass complete"
        );

        if args.once {
            return Ok(());
        }

        sleep(Duration::from_secs(args.poll_interval_secs)).await;
    }
}

fn relayer_config(args: &Args) -> RelayerConfig {
    let mut config = RelayerConfig::new(
        args.contract_address.clone(),
        args.cursor_path.clone(),
        args.start_block,
    );
    config.confirmation_depth = args.confirmation_depth;
    config.reorg_validation_depth = args.reorg_validation_depth;
    config.max_blocks_per_batch = args.max_blocks_per_batch;
    config.retry = RetryPolicy {
        max_attempts: args.retry_attempts,
        backoff_secs: args.retry_backoff_secs,
    };
    config
}

fn monero_claim_config(args: &Args) -> Result<MoneroClaimConfig> {
    let partial_spend_key_hex = arg_or_env(
        args.partial_spend_key_hex.clone(),
        "--partial-spend-key-hex",
        "RELAYER_PARTIAL_SPEND_KEY_HEX",
    )?;
    let claim_destination = arg_or_env(
        args.claim_destination.clone(),
        "--claim-destination",
        "RELAYER_CLAIM_DESTINATION",
    )?;
    let wallet_dir = arg_or_env(args.wallet_dir.clone(), "--wallet-dir", "MONERO_WALLET_DIR")?;
    let restore_height = args
        .restore_height
        .or_else(|| {
            std::env::var("RELAYER_MONERO_RESTORE_HEIGHT")
                .ok()
                .and_then(|value| value.parse().ok())
        })
        .ok_or_else(|| anyhow!("Missing --restore-height or RELAYER_MONERO_RESTORE_HEIGHT"))?;

    if !std::path::Path::new(&wallet_dir).is_dir() {
        anyhow::bail!(
            "Wallet dir {} is not a local directory. Run this inside the Monero VM or mount the wallet directory locally.",
            wallet_dir
        );
    }

    Ok(MoneroClaimConfig {
        wallet_rpc_url: args.wallet_rpc_url.clone(),
        daemon_rpc_url: args.daemon_rpc_url.clone(),
        wallet_dir,
        partial_spend_key: Zeroizing::new(parse_secret_key(&partial_spend_key_hex)?),
        claim_destination,
        restore_height,
        network: parse_network(&args.monero_network)?,
    })
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

fn arg_or_env(value: Option<String>, flag_name: &str, env_name: &str) -> Result<String> {
    value
        .or_else(|| std::env::var(env_name).ok())
        .filter(|value| !value.trim().is_empty())
        .ok_or_else(|| anyhow!("Missing {} or {}", flag_name, env_name))
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
