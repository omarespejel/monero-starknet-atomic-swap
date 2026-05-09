//! Monero wallet-rpc reveal relayer for XMR -> Starknet swaps.
//!
//! This binary waits until a wallet-rpc-observed Monero transfer reaches the
//! required amount and confirmation depth, then delegates the signed Starknet
//! reveal to the maintained `scripts/atomic_lock_sncast_ops.sh reveal` helper.
//! It intentionally does not accept Starknet private keys or implement Rust
//! Starknet transaction signing.

use anyhow::{anyhow, bail, Context, Result};
use clap::Parser;
use reqwest::Client;
use serde_json::json;
use std::path::PathBuf;
use std::process::Stdio;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::process::Command;
use tokio::time::sleep;
use tracing::{info, warn};
use zeroize::{Zeroize, Zeroizing};

use xmr_secret_gen::monero_wallet::types::TransferInfo;

const MAX_CONSECUTIVE_RPC_ERRORS: u32 = 10;
const DEFAULT_CLAIM_GRACE_SECS: u64 = 7_200;

#[derive(Parser)]
#[command(name = "relay_reveal")]
#[command(about = "Wait for Monero wallet-rpc payment, then reveal via sncast helper")]
struct Args {
    /// Starknet RPC URL (default: Sepolia)
    #[arg(
        long,
        default_value = "https://api.zan.top/public/starknet-sepolia/rpc/v0_10"
    )]
    starknet_rpc: String,

    /// Starknet network passed to the sncast helper. Mainnet is intentionally refused by the helper.
    #[arg(long, default_value = "sepolia")]
    starknet_network: String,

    /// sncast account name.
    #[arg(long, default_value = "stealth-deployer-2026-01-21")]
    sncast_account: String,

    /// sncast accounts file. Defaults to sncast's configured operator file if omitted.
    #[arg(long)]
    sncast_accounts_file: Option<PathBuf>,

    /// AtomicLock contract address (hex, 0x...)
    #[arg(long)]
    contract_address: String,

    /// Path to scripts/atomic_lock_sncast_ops.sh.
    #[arg(long, default_value = "scripts/atomic_lock_sncast_ops.sh")]
    atomic_lock_ops_script: PathBuf,

    /// Optional token address for helper state/balance output.
    #[arg(long)]
    token_address: Option<String>,

    /// File containing the 32-byte reveal secret as hex. Prefer this over env for operator runs.
    #[arg(long)]
    secret_file: Option<PathBuf>,

    /// Monero wallet-rpc URL for the wallet that can see the incoming swap payment.
    #[arg(long, default_value = "http://127.0.0.1:38090/json_rpc")]
    wallet_rpc_url: String,

    /// Optional Monero txid to monitor. If omitted, scan inbound wallet transfers.
    #[arg(long)]
    monero_txid: Option<String>,

    /// Required incoming Monero amount in piconero.
    #[arg(long)]
    expected_monero_amount_piconero: u64,

    /// Required Monero confirmations before Starknet reveal.
    #[arg(long, default_value_t = 10)]
    confirmations: u64,

    /// Poll interval in seconds.
    #[arg(long, default_value_t = 20)]
    poll_interval_secs: u64,

    /// Maximum wait time in seconds. 0 means no timeout.
    #[arg(long, default_value_t = 0)]
    timeout_secs: u64,

    /// Verify payment/finality but do not invoke sncast.
    #[arg(long)]
    dry_run: bool,

    /// After a successful reveal, wait for the grace period and claim tokens with the same account.
    #[arg(long)]
    claim_after_reveal: bool,

    /// Seconds to wait after reveal before the first claim attempt.
    #[arg(long, default_value_t = DEFAULT_CLAIM_GRACE_SECS)]
    claim_grace_secs: u64,

    /// Seconds between claim retries after the grace wait.
    #[arg(long, default_value_t = 30)]
    claim_retry_interval_secs: u64,

    /// Maximum seconds to keep retrying claim after the grace wait. 0 means try once.
    #[arg(long, default_value_t = 1_800)]
    claim_timeout_secs: u64,
}

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_max_level(tracing::Level::INFO)
        .init();

    let args = Args::parse();
    let mut secret =
        load_secret(args.secret_file.as_ref()).context("Failed to load reveal secret")?;
    validate_secret_hex(secret.as_str()).context("Invalid reveal secret")?;

    info!(
        txid = args.monero_txid.as_deref().unwrap_or("<scan-wallet>"),
        expected_amount_piconero = args.expected_monero_amount_piconero,
        confirmations = args.confirmations,
        "waiting for Monero payment"
    );

    let transfer = wait_for_payment(&args).await?;
    info!(
        txid = %transfer.txid,
        amount_piconero = transfer.amount,
        confirmations = transfer.confirmations,
        height = transfer.height,
        "Monero payment reached reveal threshold"
    );

    if args.dry_run {
        info!(
            contract = %args.contract_address,
            "dry run complete; Starknet reveal not submitted"
        );
        secret.zeroize();
        return Ok(());
    }

    let output = reveal_with_sncast(&args, secret.as_str()).await;
    secret.zeroize();
    output?;

    if args.claim_after_reveal {
        claim_after_grace(&args).await?;
    }

    Ok(())
}

fn load_secret(secret_file: Option<&PathBuf>) -> Result<Zeroizing<String>> {
    let raw = match secret_file {
        Some(path) => std::fs::read_to_string(path)
            .with_context(|| format!("Failed to read secret file {}", path.display()))?,
        None => std::env::var("ATOMIC_SWAP_SECRET_HEX")
            .context("Set ATOMIC_SWAP_SECRET_HEX or pass --secret-file")?,
    };
    Ok(Zeroizing::new(raw.trim().to_owned()))
}

fn validate_secret_hex(secret: &str) -> Result<()> {
    let trimmed = secret.trim();
    let hex = trimmed.strip_prefix("0x").unwrap_or(trimmed);
    if hex.len() != 64 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        bail!("secret must be exactly 32 bytes / 64 hex chars");
    }
    Ok(())
}

async fn wait_for_payment(args: &Args) -> Result<TransferInfo> {
    let started = Instant::now();
    let mut consecutive_errors = 0u32;

    loop {
        if args.timeout_secs > 0 && started.elapsed().as_secs() > args.timeout_secs {
            match args.monero_txid.as_deref() {
                Some(txid) => bail!(
                    "timed out waiting for {} confirmations on Monero tx {}",
                    args.confirmations,
                    txid
                ),
                None => bail!(
                    "timed out waiting for {} confirmations on inbound Monero payment",
                    args.confirmations
                ),
            }
        }

        match get_candidate_transfer(args).await {
            Ok(Some(info)) => {
                consecutive_errors = 0;
                if info.amount < args.expected_monero_amount_piconero {
                    if let Some(txid) = args.monero_txid.as_deref() {
                        bail!(
                            "Monero tx {} amount {} piconero is below expected {} piconero",
                            txid,
                            info.amount,
                            args.expected_monero_amount_piconero
                        );
                    }
                    info!(
                        txid = %info.txid,
                        amount_piconero = info.amount,
                        expected_piconero = args.expected_monero_amount_piconero,
                        "inbound Monero transfer is below expected amount"
                    );
                }
                if info.amount >= args.expected_monero_amount_piconero
                    && info.confirmations >= args.confirmations
                {
                    if transfer_unlock_satisfied(&info) {
                        return Ok(info);
                    }
                    info!(
                        txid = %info.txid,
                        unlock_time = info.unlock_time,
                        "Monero transfer has enough confirmations but remains locked"
                    );
                }
                info!(
                    txid = %info.txid,
                    amount_piconero = info.amount,
                    confirmations = info.confirmations,
                    required_confirmations = args.confirmations,
                    "waiting for more Monero confirmations"
                );
            }
            Ok(None) => {
                consecutive_errors = 0;
                if let Some(txid) = args.monero_txid.as_deref() {
                    warn!(txid, "Monero tx not visible to wallet-rpc yet");
                } else {
                    warn!("No inbound Monero transfer visible to wallet-rpc yet");
                }
            }
            Err(err) => {
                consecutive_errors += 1;
                warn!(
                    txid = args.monero_txid.as_deref().unwrap_or("<scan-wallet>"),
                    consecutive_errors,
                    max_errors = MAX_CONSECUTIVE_RPC_ERRORS,
                    error = %err,
                    "Monero wallet-rpc poll failed"
                );
                if consecutive_errors >= MAX_CONSECUTIVE_RPC_ERRORS {
                    return Err(err).context("too many consecutive Monero wallet-rpc errors");
                }
            }
        }

        sleep(Duration::from_secs(args.poll_interval_secs)).await;
    }
}

async fn get_candidate_transfer(args: &Args) -> Result<Option<TransferInfo>> {
    match args.monero_txid.as_deref() {
        Some(txid) => get_wallet_transfer(&args.wallet_rpc_url, txid).await,
        None => {
            get_wallet_inbound_transfer(&args.wallet_rpc_url, args.expected_monero_amount_piconero)
                .await
        }
    }
}

async fn get_wallet_transfer(wallet_rpc_url: &str, txid: &str) -> Result<Option<TransferInfo>> {
    let client = Client::new();
    let resp: serde_json::Value = client
        .post(wallet_rpc_url)
        .json(&json!({
            "jsonrpc": "2.0",
            "id": "0",
            "method": "get_transfer_by_txid",
            "params": { "txid": txid }
        }))
        .send()
        .await
        .context("wallet-rpc request failed")?
        .json()
        .await
        .context("failed to parse wallet-rpc response")?;

    parse_wallet_transfer_response(txid, &resp)
}

async fn get_wallet_inbound_transfer(
    wallet_rpc_url: &str,
    expected_amount_piconero: u64,
) -> Result<Option<TransferInfo>> {
    let client = Client::new();
    let resp: serde_json::Value = client
        .post(wallet_rpc_url)
        .json(&json!({
            "jsonrpc": "2.0",
            "id": "0",
            "method": "get_transfers",
            "params": {
                "in": true,
                "pool": true
            }
        }))
        .send()
        .await
        .context("wallet-rpc request failed")?
        .json()
        .await
        .context("failed to parse wallet-rpc response")?;

    parse_wallet_transfers_response(&resp, expected_amount_piconero)
}

fn parse_wallet_transfer_response(
    txid: &str,
    resp: &serde_json::Value,
) -> Result<Option<TransferInfo>> {
    if let Some(error) = resp.get("error") {
        let message = error
            .get("message")
            .and_then(|value| value.as_str())
            .unwrap_or("unknown wallet-rpc error");
        if message.to_ascii_lowercase().contains("not found") {
            return Ok(None);
        }
        return Err(anyhow!("Monero wallet-rpc error: {}", message));
    }

    let transfer = resp
        .get("result")
        .and_then(|result| result.get("transfer"))
        .ok_or_else(|| anyhow!("wallet-rpc response missing result.transfer"))?;

    let transfer_type = transfer
        .get("type")
        .and_then(|value| value.as_str())
        .unwrap_or("unknown");
    if transfer_type != "in" {
        bail!(
            "wallet-rpc transfer {} has type {}, expected inbound transfer",
            txid,
            transfer_type
        );
    }

    Ok(Some(TransferInfo {
        txid: txid.to_owned(),
        amount: transfer
            .get("amount")
            .and_then(|value| value.as_u64())
            .ok_or_else(|| anyhow!("wallet-rpc transfer missing amount"))?,
        confirmations: transfer
            .get("confirmations")
            .and_then(|value| value.as_u64())
            .unwrap_or(0),
        height: transfer
            .get("height")
            .and_then(|value| value.as_u64())
            .unwrap_or(0),
        unlock_time: transfer
            .get("unlock_time")
            .and_then(|value| value.as_u64())
            .unwrap_or(0),
    }))
}

fn parse_wallet_transfers_response(
    resp: &serde_json::Value,
    expected_amount_piconero: u64,
) -> Result<Option<TransferInfo>> {
    if let Some(error) = resp.get("error") {
        let message = error
            .get("message")
            .and_then(|value| value.as_str())
            .unwrap_or("unknown wallet-rpc error");
        return Err(anyhow!("Monero wallet-rpc error: {}", message));
    }

    let result = resp
        .get("result")
        .ok_or_else(|| anyhow!("wallet-rpc response missing result"))?;

    let mut transfers = Vec::new();
    for field in ["in", "pool"] {
        if let Some(items) = result.get(field).and_then(|value| value.as_array()) {
            for item in items {
                if let Some(info) = parse_transfer_item(item)? {
                    transfers.push(info);
                }
            }
        }
    }

    if transfers.is_empty() {
        return Ok(None);
    }

    transfers.sort_by(|left, right| {
        let left_meets = left.amount >= expected_amount_piconero;
        let right_meets = right.amount >= expected_amount_piconero;
        right_meets
            .cmp(&left_meets)
            .then_with(|| right.confirmations.cmp(&left.confirmations))
            .then_with(|| left.height.cmp(&right.height))
    });

    Ok(transfers.into_iter().next())
}

fn parse_transfer_item(transfer: &serde_json::Value) -> Result<Option<TransferInfo>> {
    let transfer_type = transfer
        .get("type")
        .and_then(|value| value.as_str())
        .unwrap_or("in");
    if transfer_type != "in" && transfer_type != "pool" {
        return Ok(None);
    }

    let Some(txid) = transfer.get("txid").and_then(|value| value.as_str()) else {
        return Ok(None);
    };

    Ok(Some(TransferInfo {
        txid: txid.to_owned(),
        amount: transfer
            .get("amount")
            .and_then(|value| value.as_u64())
            .ok_or_else(|| anyhow!("wallet-rpc transfer missing amount"))?,
        confirmations: transfer
            .get("confirmations")
            .and_then(|value| value.as_u64())
            .unwrap_or(0),
        height: transfer
            .get("height")
            .and_then(|value| value.as_u64())
            .unwrap_or(0),
        unlock_time: transfer
            .get("unlock_time")
            .and_then(|value| value.as_u64())
            .unwrap_or(0),
    }))
}

fn transfer_unlock_satisfied(info: &TransferInfo) -> bool {
    if info.unlock_time == 0 {
        return true;
    }

    // Monero unlock_time values below 500_000_000 are block heights; larger
    // values are Unix timestamps.
    if info.unlock_time < 500_000_000 {
        let current_height = info
            .height
            .saturating_add(info.confirmations.saturating_sub(1));
        return current_height >= info.unlock_time;
    }

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs())
        .unwrap_or(0);
    now >= info.unlock_time
}

async fn reveal_with_sncast(args: &Args, secret: &str) -> Result<()> {
    let script_path = resolve_ops_script(&args.atomic_lock_ops_script);
    let mut command = Command::new(&script_path);
    command
        .arg("reveal")
        .arg(&args.contract_address)
        .env("STARKNET_NETWORK", &args.starknet_network)
        .env("STARKNET_RPC_URL", &args.starknet_rpc)
        .env("SNCAST_ACCOUNT", &args.sncast_account)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    if let Some(secret_file) = args.secret_file.as_ref() {
        command.env("ATOMIC_SWAP_SECRET_FILE", secret_file);
    } else {
        command.env("ATOMIC_SWAP_SECRET_HEX", secret);
    }
    if let Some(accounts_file) = args.sncast_accounts_file.as_ref() {
        command.env("SNCAST_ACCOUNTS_FILE", accounts_file);
    }
    if let Some(token) = args.token_address.as_ref() {
        command.env("ATOMIC_SWAP_TOKEN_ADDRESS", token);
    }

    let output = command
        .output()
        .await
        .with_context(|| format!("failed to execute {}", script_path.display()))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);
    let redacted_stdout = redact_secret(&stdout, secret);
    let redacted_stderr = redact_secret(&stderr, secret);

    if !redacted_stdout.trim().is_empty() {
        info!(output = %redacted_stdout.trim(), "sncast reveal helper stdout");
    }
    if !redacted_stderr.trim().is_empty() {
        warn!(output = %redacted_stderr.trim(), "sncast reveal helper stderr");
    }

    if !output.status.success() {
        bail!(
            "sncast reveal helper failed with status {}",
            output
                .status
                .code()
                .map(|code| code.to_string())
                .unwrap_or_else(|| "signal".to_string())
        );
    }

    Ok(())
}

async fn claim_after_grace(args: &Args) -> Result<()> {
    info!(
        grace_secs = args.claim_grace_secs,
        retry_interval_secs = args.claim_retry_interval_secs,
        timeout_secs = args.claim_timeout_secs,
        "waiting to claim Starknet tokens after reveal"
    );
    sleep(Duration::from_secs(args.claim_grace_secs)).await;

    let started = Instant::now();
    loop {
        match claim_with_sncast(args).await {
            Ok(()) => return Ok(()),
            Err(err) => {
                if args.claim_timeout_secs == 0
                    || started.elapsed().as_secs() >= args.claim_timeout_secs
                {
                    return Err(err).context("claim after reveal failed");
                }
                warn!(
                    error = %err,
                    retry_interval_secs = args.claim_retry_interval_secs,
                    "claim after reveal failed; retrying"
                );
                sleep(Duration::from_secs(args.claim_retry_interval_secs)).await;
            }
        }
    }
}

async fn claim_with_sncast(args: &Args) -> Result<()> {
    let script_path = resolve_ops_script(&args.atomic_lock_ops_script);
    let mut command = Command::new(&script_path);
    command
        .arg("claim")
        .arg(&args.contract_address)
        .env("STARKNET_NETWORK", &args.starknet_network)
        .env("STARKNET_RPC_URL", &args.starknet_rpc)
        .env("SNCAST_ACCOUNT", &args.sncast_account)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    if let Some(accounts_file) = args.sncast_accounts_file.as_ref() {
        command.env("SNCAST_ACCOUNTS_FILE", accounts_file);
    }
    if let Some(token) = args.token_address.as_ref() {
        command.env("ATOMIC_SWAP_TOKEN_ADDRESS", token);
    }

    let output = command
        .output()
        .await
        .with_context(|| format!("failed to execute {}", script_path.display()))?;

    let stdout = String::from_utf8_lossy(&output.stdout);
    let stderr = String::from_utf8_lossy(&output.stderr);

    if !stdout.trim().is_empty() {
        info!(output = %stdout.trim(), "sncast claim helper stdout");
    }
    if !stderr.trim().is_empty() {
        warn!(output = %stderr.trim(), "sncast claim helper stderr");
    }

    if !output.status.success() {
        bail!(
            "sncast claim helper failed with status {}",
            output
                .status
                .code()
                .map(|code| code.to_string())
                .unwrap_or_else(|| "signal".to_string())
        );
    }

    Ok(())
}

fn resolve_ops_script(path: &PathBuf) -> PathBuf {
    if path.exists() {
        return path.clone();
    }

    let from_rust_dir = PathBuf::from("..").join(path);
    if from_rust_dir.exists() {
        return from_rust_dir;
    }

    path.clone()
}

fn redact_secret(value: &str, secret: &str) -> String {
    let normalized = secret.trim().strip_prefix("0x").unwrap_or(secret.trim());
    let lower = normalized.to_ascii_lowercase();
    let upper = normalized.to_ascii_uppercase();
    let mut redacted = value
        .replace(secret.trim(), "<redacted-secret>")
        .replace(&format!("0x{}", lower), "0x<redacted-secret>")
        .replace(&format!("0x{}", upper), "0x<redacted-secret>")
        .replace(&lower, "<redacted-secret>")
        .replace(&upper, "<redacted-secret>");

    if lower.len() == 64 {
        redacted = redacted
            .replace(&format!("0x{}", &lower[..62]), "0x<redacted-secret-word>")
            .replace(
                &format!("0x{}", &lower[62..]),
                "0x<redacted-secret-pending>",
            );
    }

    redacted
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_secret_hex_shape() {
        assert!(validate_secret_hex(
            "1212121212121212121212121212121212121212121212121212121212121212"
        )
        .is_ok());
        assert!(validate_secret_hex(
            "0x1212121212121212121212121212121212121212121212121212121212121212"
        )
        .is_ok());
        assert!(validate_secret_hex("1234").is_err());
        assert!(validate_secret_hex(
            "zz12121212121212121212121212121212121212121212121212121212121212"
        )
        .is_err());
    }

    #[test]
    fn redacts_full_secret_and_bytearray_chunks() {
        let secret = "12121212121212121212121212121212121212121212121212121212121212ab";
        let output = format!(
            "full=0x{} word=0x{} pending=0x{}",
            secret,
            &secret[..62],
            &secret[62..]
        );
        let redacted = redact_secret(&output, secret);
        assert!(!redacted.contains(secret));
        assert!(!redacted.contains(&secret[..62]));
        assert!(!redacted.contains(&secret[62..]));
        assert!(redacted.contains("<redacted-secret>"));
    }

    #[test]
    fn parses_only_inbound_wallet_transfer() {
        let inbound = json!({
            "result": {
                "transfer": {
                    "type": "in",
                    "amount": 5_000_000_000u64,
                    "confirmations": 10u64,
                    "height": 2_000_000u64,
                    "unlock_time": 0u64
                }
            }
        });
        let parsed = parse_wallet_transfer_response("abc", &inbound)
            .unwrap()
            .unwrap();
        assert_eq!(parsed.amount, 5_000_000_000);

        let outbound = json!({
            "result": {
                "transfer": {
                    "type": "out",
                    "amount": 5_000_000_000u64,
                    "confirmations": 10u64,
                    "height": 2_000_000u64,
                    "unlock_time": 0u64
                }
            }
        });
        assert!(parse_wallet_transfer_response("abc", &outbound).is_err());
    }

    #[test]
    fn scans_wallet_transfers_by_amount_then_confirmations() {
        let resp = json!({
            "result": {
                "in": [
                    {
                        "type": "in",
                        "txid": "underpaid",
                        "amount": 4_000_000_000u64,
                        "confirmations": 100u64,
                        "height": 10u64,
                        "unlock_time": 0u64
                    },
                    {
                        "type": "in",
                        "txid": "candidate_low_conf",
                        "amount": 5_000_000_000u64,
                        "confirmations": 2u64,
                        "height": 20u64,
                        "unlock_time": 0u64
                    },
                    {
                        "type": "in",
                        "txid": "candidate_high_conf",
                        "amount": 5_000_000_000u64,
                        "confirmations": 12u64,
                        "height": 21u64,
                        "unlock_time": 0u64
                    }
                ]
            }
        });

        let parsed = parse_wallet_transfers_response(&resp, 5_000_000_000)
            .unwrap()
            .unwrap();
        assert_eq!(parsed.txid, "candidate_high_conf");
    }

    #[test]
    fn scan_mode_keeps_underpaid_transfer_visible() {
        let resp = json!({
            "result": {
                "in": [
                    {
                        "type": "in",
                        "txid": "underpaid",
                        "amount": 4_000_000_000u64,
                        "confirmations": 100u64,
                        "height": 10u64,
                        "unlock_time": 0u64
                    }
                ]
            }
        });

        let parsed = parse_wallet_transfers_response(&resp, 5_000_000_000)
            .unwrap()
            .unwrap();
        assert_eq!(parsed.txid, "underpaid");
        assert_eq!(parsed.amount, 4_000_000_000);
    }

    #[test]
    fn checks_block_height_unlock_time() {
        let locked = TransferInfo {
            txid: "abc".to_string(),
            amount: 1,
            confirmations: 3,
            height: 100,
            unlock_time: 105,
        };
        assert!(!transfer_unlock_satisfied(&locked));

        let unlocked = TransferInfo {
            confirmations: 6,
            ..locked
        };
        assert!(transfer_unlock_satisfied(&unlocked));
    }
}
