//! Durable Starknet-to-Monero relayer loop.
//!
//! This module observes finalized-enough Starknet `SecretRevealed` events,
//! extracts the full revealed secret from transaction calldata, and dispatches
//! it to a Monero-side claimant. It is intentionally generic over the Starknet
//! event source and Monero claimant so the retry/cursor/reorg logic is unit
//! testable without live RPC.

use anyhow::{anyhow, Context, Result};
use async_trait::async_trait;
use curve25519_dalek::scalar::Scalar;
use monero::Network;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::future::Future;
use std::path::PathBuf;
use std::time::Duration;
use tokio::time::sleep;
use zeroize::{Zeroize, Zeroizing};

use crate::monero::claim_monero_after_reveal;
use crate::monero_wallet::MoneroWallet;
use crate::starknet::{AtomicLockEvent, StarknetEventMeta};

#[derive(Debug, Clone)]
pub struct RelayerConfig {
    pub contract_address: String,
    pub cursor_path: PathBuf,
    pub start_block: u64,
    /// Number of Starknet blocks to leave unprocessed to avoid short reorgs.
    pub confirmation_depth: u64,
    /// Number of previously finalized blocks to keep validating for reorgs.
    pub reorg_validation_depth: u64,
    pub max_blocks_per_batch: u64,
    pub retry: RetryPolicy,
}

impl RelayerConfig {
    pub fn new(contract_address: String, cursor_path: PathBuf, start_block: u64) -> Self {
        Self {
            contract_address,
            cursor_path,
            start_block,
            confirmation_depth: 6,
            reorg_validation_depth: 64,
            max_blocks_per_batch: 100,
            retry: RetryPolicy::default(),
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct RetryPolicy {
    pub max_attempts: u32,
    pub backoff_secs: u64,
}

impl Default for RetryPolicy {
    fn default() -> Self {
        Self {
            max_attempts: 5,
            backoff_secs: 5,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct RelayerCursor {
    pub next_block: u64,
    pub processed_event_ids: BTreeSet<String>,
    #[serde(default)]
    pub finalized_block_hashes: BTreeMap<u64, String>,
}

impl RelayerCursor {
    fn new(start_block: u64) -> Self {
        Self {
            next_block: start_block,
            processed_event_ids: BTreeSet::new(),
            finalized_block_hashes: BTreeMap::new(),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SecretReveal {
    pub event_id: String,
    pub contract_address: String,
    pub tx_hash: String,
    pub block_number: u64,
    pub revealer: String,
    pub secret_hash: String,
    pub claimable_after: u64,
    pub secret: [u8; 32],
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct RelayerRunStats {
    pub latest_block: u64,
    pub safe_tip: Option<u64>,
    pub from_block: u64,
    pub to_block: Option<u64>,
    pub events_seen: usize,
    pub reveals_claimed: usize,
    pub events_skipped: usize,
}

#[async_trait]
pub trait StarknetSecretEventSource: Send + Sync {
    async fn latest_block_number(&self) -> Result<u64>;

    async fn block_hash(&self, block_number: u64) -> Result<String>;

    async fn atomic_lock_events(
        &self,
        contract_address: &str,
        from_block: u64,
        to_block: u64,
    ) -> Result<Vec<AtomicLockEvent>>;

    async fn reveal_secret_from_transaction(
        &self,
        tx_hash: &str,
        contract_address: &str,
    ) -> Result<Option<[u8; 32]>>;
}

#[async_trait]
pub trait MoneroSecretClaimant: Send + Sync {
    async fn claim_revealed_secret(&self, reveal: &SecretReveal) -> Result<String>;
}

pub struct MoneroClaimConfig {
    pub wallet_rpc_url: String,
    pub daemon_rpc_url: String,
    pub wallet_dir: String,
    pub partial_spend_key: Zeroizing<[u8; 32]>,
    pub claim_destination: String,
    pub restore_height: u64,
    pub network: Network,
}

pub struct MoneroWalletSecretClaimant {
    config: MoneroClaimConfig,
}

impl MoneroWalletSecretClaimant {
    pub fn new(config: MoneroClaimConfig) -> Self {
        Self { config }
    }
}

#[async_trait]
impl MoneroSecretClaimant for MoneroWalletSecretClaimant {
    async fn claim_revealed_secret(&self, reveal: &SecretReveal) -> Result<String> {
        let wallet = MoneroWallet::new(
            self.config.wallet_rpc_url.clone(),
            self.config.daemon_rpc_url.clone(),
            format!("relayer_{}", sanitize_wallet_name(&reveal.contract_address)),
            self.config.wallet_dir.clone(),
        )
        .await
        .context("Failed to initialize Monero wallet-rpc claimant")?;

        let x_partial =
            Zeroizing::new(Scalar::from_bytes_mod_order(*self.config.partial_spend_key));

        let mut secret = reveal.secret;
        let t = Scalar::from_bytes_mod_order(secret);
        secret.zeroize();

        claim_monero_after_reveal(
            &wallet,
            x_partial,
            t,
            &self.config.claim_destination,
            self.config.restore_height,
            self.config.network,
        )
        .await
    }
}

pub struct SecretRevealRelayer {
    config: RelayerConfig,
}

impl SecretRevealRelayer {
    pub fn new(config: RelayerConfig) -> Self {
        Self { config }
    }

    pub async fn run_once<S, M>(&self, source: &S, claimant: &M) -> Result<RelayerRunStats>
    where
        S: StarknetSecretEventSource,
        M: MoneroSecretClaimant,
    {
        let mut cursor = self.load_cursor()?;
        let latest_block = retry_async(self.config.retry, "starknet latest block", || {
            source.latest_block_number()
        })
        .await?;

        let Some(safe_tip) = latest_block.checked_sub(self.config.confirmation_depth) else {
            return Ok(RelayerRunStats {
                latest_block,
                safe_tip: None,
                from_block: cursor.next_block,
                ..RelayerRunStats::default()
            });
        };

        if cursor.next_block > safe_tip {
            return Ok(RelayerRunStats {
                latest_block,
                safe_tip: Some(safe_tip),
                from_block: cursor.next_block,
                ..RelayerRunStats::default()
            });
        }

        self.rewind_cursor_on_reorg(source, &mut cursor, safe_tip)
            .await?;

        if cursor.next_block > safe_tip {
            return Ok(RelayerRunStats {
                latest_block,
                safe_tip: Some(safe_tip),
                from_block: cursor.next_block,
                ..RelayerRunStats::default()
            });
        }

        let to_block = safe_tip.min(
            cursor
                .next_block
                .saturating_add(self.config.max_blocks_per_batch.saturating_sub(1)),
        );
        let from_block = cursor.next_block;

        let events = retry_async(self.config.retry, "starknet event page", || {
            source.atomic_lock_events(&self.config.contract_address, from_block, to_block)
        })
        .await?;

        let mut stats = RelayerRunStats {
            latest_block,
            safe_tip: Some(safe_tip),
            from_block,
            to_block: Some(to_block),
            events_seen: events.len(),
            ..RelayerRunStats::default()
        };

        for event in events {
            let Some(pending) = PendingSecretReveal::try_from_event(&event)? else {
                stats.events_skipped += 1;
                continue;
            };

            if cursor.processed_event_ids.contains(&pending.event_id) {
                stats.events_skipped += 1;
                continue;
            }

            let tx_hash = pending.tx_hash.clone();
            let secret = retry_async(self.config.retry, "starknet reveal calldata", || {
                source.reveal_secret_from_transaction(&tx_hash, &self.config.contract_address)
            })
            .await?
            .ok_or_else(|| anyhow!("No reveal_secret calldata found for tx {}", tx_hash))?;

            verify_secret_hash_word(&secret, &pending.secret_hash)?;
            let reveal = pending.into_reveal(self.config.contract_address.clone(), secret);
            let monero_txid =
                retry_async(self.config.retry, "monero claim revealed secret", || {
                    claimant.claim_revealed_secret(&reveal)
                })
                .await?;
            tracing::info!(
                event_id = reveal.event_id,
                starknet_tx_hash = reveal.tx_hash,
                monero_txid = monero_txid,
                "Monero claim submitted for revealed Starknet secret"
            );

            cursor.processed_event_ids.insert(reveal.event_id);
            self.save_cursor(&cursor)?;
            stats.reveals_claimed += 1;
        }

        self.record_finalized_block_hashes(source, &mut cursor, from_block, to_block)
            .await?;
        cursor.next_block = to_block.saturating_add(1);
        let retain_from = cursor
            .next_block
            .saturating_sub(self.config.reorg_validation_depth);
        trim_finalized_hashes(&mut cursor, retain_from);
        self.save_cursor(&cursor)?;

        Ok(stats)
    }

    fn load_cursor(&self) -> Result<RelayerCursor> {
        match fs::read_to_string(&self.config.cursor_path) {
            Ok(raw) => {
                let mut cursor: RelayerCursor =
                    serde_json::from_str(&raw).context("Failed to parse relayer cursor")?;
                if cursor.next_block < self.config.start_block {
                    cursor.next_block = self.config.start_block;
                }
                Ok(cursor)
            }
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                Ok(RelayerCursor::new(self.config.start_block))
            }
            Err(err) => Err(err).context("Failed to read relayer cursor"),
        }
    }

    async fn rewind_cursor_on_reorg<S>(
        &self,
        source: &S,
        cursor: &mut RelayerCursor,
        safe_tip: u64,
    ) -> Result<()>
    where
        S: StarknetSecretEventSource,
    {
        let validate_from = cursor
            .next_block
            .saturating_sub(self.config.reorg_validation_depth)
            .max(self.config.start_block);

        let mut rewind_to = None;
        for (block_number, expected_hash) in cursor
            .finalized_block_hashes
            .range(validate_from..cursor.next_block)
        {
            if *block_number > safe_tip {
                continue;
            }
            let current_hash = retry_async(self.config.retry, "starknet block hash", || {
                source.block_hash(*block_number)
            })
            .await?;
            if &current_hash != expected_hash {
                rewind_to = Some(
                    rewind_to.map_or(*block_number, |current: u64| current.min(*block_number)),
                );
                break;
            }
        }

        if let Some(block_number) = rewind_to {
            tracing::warn!(
                "Starknet reorg detected in retained cursor window; rewinding from block {} to {}",
                cursor.next_block,
                block_number
            );
            cursor.next_block = block_number;
            cursor.processed_event_ids.retain(|event_id| {
                event_id_block(event_id).map_or(false, |block| block < block_number)
            });
            cursor
                .finalized_block_hashes
                .retain(|block, _| *block < block_number);
            self.save_cursor(cursor)?;
        }

        Ok(())
    }

    async fn record_finalized_block_hashes<S>(
        &self,
        source: &S,
        cursor: &mut RelayerCursor,
        from_block: u64,
        to_block: u64,
    ) -> Result<()>
    where
        S: StarknetSecretEventSource,
    {
        for block_number in from_block..=to_block {
            let block_hash = retry_async(self.config.retry, "starknet block hash", || {
                source.block_hash(block_number)
            })
            .await?;
            cursor
                .finalized_block_hashes
                .insert(block_number, block_hash);
        }

        Ok(())
    }

    fn save_cursor(&self, cursor: &RelayerCursor) -> Result<()> {
        if let Some(parent) = self.config.cursor_path.parent() {
            fs::create_dir_all(parent).context("Failed to create relayer cursor directory")?;
        }

        let tmp_path = self.config.cursor_path.with_extension("tmp");
        let raw = serde_json::to_string_pretty(cursor).context("Failed to serialize cursor")?;
        fs::write(&tmp_path, raw + "\n").context("Failed to write temporary relayer cursor")?;
        fs::rename(&tmp_path, &self.config.cursor_path).context("Failed to persist relayer cursor")
    }
}

fn event_id_block(event_id: &str) -> Option<u64> {
    event_id.split(':').next()?.parse().ok()
}

fn trim_finalized_hashes(cursor: &mut RelayerCursor, retain_from: u64) {
    cursor
        .finalized_block_hashes
        .retain(|block_number, _| *block_number >= retain_from);
}

fn verify_secret_hash_word(secret: &[u8; 32], event_secret_hash: &str) -> Result<()> {
    let digest = Sha256::digest(secret);
    let first_word = u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]]);
    let expected = normalize_hex(&format!("0x{:x}", first_word));
    let observed = normalize_hex(event_secret_hash);

    if observed != expected {
        anyhow::bail!(
            "SecretRevealed event hash word mismatch: observed {}, expected {}",
            observed,
            expected
        );
    }

    Ok(())
}

fn sanitize_wallet_name(input: &str) -> String {
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

fn normalize_hex(input: &str) -> String {
    let trimmed = input.trim();
    let without_prefix = trimmed
        .strip_prefix("0x")
        .or_else(|| trimmed.strip_prefix("0X"))
        .unwrap_or(trimmed);
    let normalized = without_prefix.trim_start_matches('0').to_ascii_lowercase();
    if normalized.is_empty() {
        "0x0".to_string()
    } else {
        format!("0x{}", normalized)
    }
}

struct PendingSecretReveal {
    event_id: String,
    tx_hash: String,
    block_number: u64,
    revealer: String,
    secret_hash: String,
    claimable_after: u64,
}

impl PendingSecretReveal {
    fn try_from_event(event: &AtomicLockEvent) -> Result<Option<Self>> {
        let AtomicLockEvent::SecretRevealed {
            meta,
            revealer,
            secret_hash,
            claimable_after,
        } = event
        else {
            return Ok(None);
        };

        let block_number = meta
            .block_number
            .ok_or_else(|| anyhow!("SecretRevealed event missing block_number"))?;

        Ok(Some(Self {
            event_id: event_id("SecretRevealed", meta, block_number)?,
            tx_hash: meta.transaction_hash.clone(),
            block_number,
            revealer: revealer.clone(),
            secret_hash: secret_hash.clone(),
            claimable_after: *claimable_after,
        }))
    }

    fn into_reveal(self, contract_address: String, secret: [u8; 32]) -> SecretReveal {
        SecretReveal {
            event_id: self.event_id,
            contract_address,
            tx_hash: self.tx_hash,
            block_number: self.block_number,
            revealer: self.revealer,
            secret_hash: self.secret_hash,
            claimable_after: self.claimable_after,
            secret,
        }
    }
}

fn event_id(kind: &str, meta: &StarknetEventMeta, block_number: u64) -> Result<String> {
    if meta.transaction_hash == "0x0" {
        anyhow::bail!("{} event missing transaction_hash", kind);
    }
    Ok(format!(
        "{}:{}:{}",
        block_number, meta.transaction_hash, kind
    ))
}

async fn retry_async<F, Fut, T>(policy: RetryPolicy, label: &str, mut op: F) -> Result<T>
where
    F: FnMut() -> Fut,
    Fut: Future<Output = Result<T>>,
{
    let attempts = policy.max_attempts.max(1);
    let mut last_error = None;

    for attempt in 1..=attempts {
        match op().await {
            Ok(value) => return Ok(value),
            Err(err) => {
                tracing::warn!(
                    "{} failed on attempt {}/{}: {}",
                    label,
                    attempt,
                    attempts,
                    err
                );
                last_error = Some(err);
                if attempt < attempts && policy.backoff_secs > 0 {
                    sleep(Duration::from_secs(policy.backoff_secs)).await;
                }
            }
        }
    }

    Err(last_error
        .unwrap_or_else(|| anyhow!("{} failed without returning an error", label))
        .context(format!("{} failed after {} attempts", label, attempts)))
}

#[async_trait]
impl StarknetSecretEventSource for crate::starknet::StarknetClient {
    async fn latest_block_number(&self) -> Result<u64> {
        self.get_block_number().await
    }

    async fn block_hash(&self, block_number: u64) -> Result<String> {
        self.get_block_hash(block_number).await
    }

    async fn atomic_lock_events(
        &self,
        contract_address: &str,
        from_block: u64,
        to_block: u64,
    ) -> Result<Vec<AtomicLockEvent>> {
        self.get_atomic_lock_events(contract_address, Some(from_block), Some(to_block))
            .await
    }

    async fn reveal_secret_from_transaction(
        &self,
        tx_hash: &str,
        contract_address: &str,
    ) -> Result<Option<[u8; 32]>> {
        self.get_reveal_secret_from_transaction(tx_hash, contract_address)
            .await
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;
    use std::sync::atomic::{AtomicUsize, Ordering};
    use std::sync::{Arc, Mutex};

    #[derive(Default)]
    struct MockSource {
        latest: u64,
        events: Vec<AtomicLockEvent>,
        secrets: HashMap<String, [u8; 32]>,
        block_hashes: HashMap<u64, String>,
        event_failures: AtomicUsize,
    }

    #[async_trait]
    impl StarknetSecretEventSource for MockSource {
        async fn latest_block_number(&self) -> Result<u64> {
            Ok(self.latest)
        }

        async fn block_hash(&self, block_number: u64) -> Result<String> {
            Ok(self
                .block_hashes
                .get(&block_number)
                .cloned()
                .unwrap_or_else(|| format!("0x{:x}", block_number)))
        }

        async fn atomic_lock_events(
            &self,
            _contract_address: &str,
            from_block: u64,
            to_block: u64,
        ) -> Result<Vec<AtomicLockEvent>> {
            if self.event_failures.load(Ordering::SeqCst) > 0 {
                self.event_failures.fetch_sub(1, Ordering::SeqCst);
                anyhow::bail!("transient event fetch failure");
            }

            Ok(self
                .events
                .iter()
                .filter(|event| match event {
                    AtomicLockEvent::SecretRevealed { meta, .. } => meta
                        .block_number
                        .map(|block| block >= from_block && block <= to_block)
                        .unwrap_or(false),
                    _ => false,
                })
                .cloned()
                .collect())
        }

        async fn reveal_secret_from_transaction(
            &self,
            tx_hash: &str,
            _contract_address: &str,
        ) -> Result<Option<[u8; 32]>> {
            Ok(self.secrets.get(tx_hash).copied())
        }
    }

    #[derive(Default)]
    struct MockClaimant {
        claimed: Mutex<Vec<SecretReveal>>,
        failures: AtomicUsize,
    }

    #[async_trait]
    impl MoneroSecretClaimant for MockClaimant {
        async fn claim_revealed_secret(&self, reveal: &SecretReveal) -> Result<String> {
            if self.failures.load(Ordering::SeqCst) > 0 {
                self.failures.fetch_sub(1, Ordering::SeqCst);
                anyhow::bail!("transient monero claim failure");
            }

            self.claimed.lock().unwrap().push(reveal.clone());
            Ok("stagenet-claim-tx".to_string())
        }
    }

    fn config(path: PathBuf) -> RelayerConfig {
        RelayerConfig {
            contract_address: "0xabc".to_string(),
            cursor_path: path,
            start_block: 100,
            confirmation_depth: 5,
            reorg_validation_depth: 20,
            max_blocks_per_batch: 10,
            retry: RetryPolicy {
                max_attempts: 3,
                backoff_secs: 0,
            },
        }
    }

    fn secret_event(block: u64, tx_hash: &str) -> AtomicLockEvent {
        AtomicLockEvent::SecretRevealed {
            meta: StarknetEventMeta {
                transaction_hash: tx_hash.to_string(),
                block_number: Some(block),
            },
            revealer: "0x123".to_string(),
            secret_hash: secret_hash_word([0x12; 32]),
            claimable_after: 1234,
        }
    }

    fn secret_hash_word(secret: [u8; 32]) -> String {
        let digest = Sha256::digest(secret);
        format!(
            "0x{:x}",
            u32::from_be_bytes([digest[0], digest[1], digest[2], digest[3]])
        )
    }

    #[tokio::test]
    async fn waits_for_confirmation_depth_before_processing() {
        let dir = tempfile::tempdir().unwrap();
        let source = MockSource {
            latest: 103,
            events: vec![secret_event(101, "0xaaa")],
            ..MockSource::default()
        };
        let claimant = MockClaimant::default();
        let relayer = SecretRevealRelayer::new(config(dir.path().join("cursor.json")));

        let stats = relayer.run_once(&source, &claimant).await.unwrap();
        assert_eq!(stats.safe_tip, Some(98));
        assert!(claimant.claimed.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn claims_finalized_secret_and_persists_cursor() {
        let dir = tempfile::tempdir().unwrap();
        let cursor_path = dir.path().join("cursor.json");
        let mut secrets = HashMap::new();
        secrets.insert("0xaaa".to_string(), [0x12; 32]);
        let source = MockSource {
            latest: 120,
            events: vec![secret_event(101, "0xaaa")],
            secrets,
            ..MockSource::default()
        };
        let claimant = MockClaimant::default();
        let relayer = SecretRevealRelayer::new(config(cursor_path.clone()));

        let stats = relayer.run_once(&source, &claimant).await.unwrap();
        assert_eq!(stats.reveals_claimed, 1);
        assert_eq!(claimant.claimed.lock().unwrap()[0].secret, [0x12; 32]);

        let cursor: RelayerCursor =
            serde_json::from_str(&fs::read_to_string(cursor_path).unwrap()).unwrap();
        assert_eq!(cursor.next_block, 110);
        assert_eq!(cursor.processed_event_ids.len(), 1);
    }

    #[tokio::test]
    async fn does_not_reprocess_persisted_event() {
        let dir = tempfile::tempdir().unwrap();
        let cursor_path = dir.path().join("cursor.json");
        let mut cursor = RelayerCursor::new(100);
        cursor
            .processed_event_ids
            .insert("101:0xaaa:SecretRevealed".to_string());
        fs::write(&cursor_path, serde_json::to_string(&cursor).unwrap()).unwrap();

        let mut secrets = HashMap::new();
        secrets.insert("0xaaa".to_string(), [0x12; 32]);
        let source = MockSource {
            latest: 120,
            events: vec![secret_event(101, "0xaaa")],
            secrets,
            ..MockSource::default()
        };
        let claimant = MockClaimant::default();
        let relayer = SecretRevealRelayer::new(config(cursor_path));

        let stats = relayer.run_once(&source, &claimant).await.unwrap();
        assert_eq!(stats.reveals_claimed, 0);
        assert_eq!(stats.events_skipped, 1);
        assert!(claimant.claimed.lock().unwrap().is_empty());
    }

    #[tokio::test]
    async fn retries_event_fetch_and_claim() {
        let dir = tempfile::tempdir().unwrap();
        let mut secrets = HashMap::new();
        secrets.insert("0xaaa".to_string(), [0x12; 32]);
        let source = MockSource {
            latest: 120,
            events: vec![secret_event(101, "0xaaa")],
            secrets,
            event_failures: AtomicUsize::new(1),
            ..MockSource::default()
        };
        let claimant = MockClaimant {
            failures: AtomicUsize::new(1),
            ..MockClaimant::default()
        };
        let relayer = SecretRevealRelayer::new(config(dir.path().join("cursor.json")));

        let stats = relayer.run_once(&source, &claimant).await.unwrap();
        assert_eq!(stats.reveals_claimed, 1);
        assert_eq!(claimant.claimed.lock().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn failed_claim_does_not_advance_cursor() {
        let dir = tempfile::tempdir().unwrap();
        let cursor_path = dir.path().join("cursor.json");
        let mut secrets = HashMap::new();
        secrets.insert("0xaaa".to_string(), [0x12; 32]);
        let source = MockSource {
            latest: 120,
            events: vec![secret_event(101, "0xaaa")],
            secrets,
            ..MockSource::default()
        };
        let claimant = MockClaimant {
            failures: AtomicUsize::new(5),
            ..MockClaimant::default()
        };
        let relayer = SecretRevealRelayer::new(config(cursor_path.clone()));

        assert!(relayer.run_once(&source, &claimant).await.is_err());
        assert!(
            !cursor_path.exists(),
            "cursor should not advance when claim never succeeds"
        );
    }

    #[tokio::test]
    async fn mismatched_event_secret_hash_does_not_claim() {
        let dir = tempfile::tempdir().unwrap();
        let cursor_path = dir.path().join("cursor.json");
        let mut secrets = HashMap::new();
        secrets.insert("0xaaa".to_string(), [0x12; 32]);
        let mut event = secret_event(101, "0xaaa");
        if let AtomicLockEvent::SecretRevealed {
            ref mut secret_hash,
            ..
        } = event
        {
            *secret_hash = "0xdeadbeef".to_string();
        }
        let source = MockSource {
            latest: 120,
            events: vec![event],
            secrets,
            ..MockSource::default()
        };
        let claimant = MockClaimant::default();
        let relayer = SecretRevealRelayer::new(config(cursor_path.clone()));

        let err = relayer.run_once(&source, &claimant).await.unwrap_err();
        assert!(err.to_string().contains("hash word mismatch"));
        assert!(claimant.claimed.lock().unwrap().is_empty());
        assert!(
            !cursor_path.exists(),
            "cursor should not advance when local hash verification fails"
        );
    }

    #[tokio::test]
    async fn rewinds_cursor_when_retained_block_hash_changes() {
        let dir = tempfile::tempdir().unwrap();
        let cursor_path = dir.path().join("cursor.json");
        let mut cursor = RelayerCursor::new(100);
        cursor.next_block = 110;
        cursor
            .processed_event_ids
            .insert("106:0xaaa:SecretRevealed".to_string());
        cursor
            .processed_event_ids
            .insert("104:0xold:SecretRevealed".to_string());
        cursor
            .finalized_block_hashes
            .insert(106, "0xold".to_string());
        fs::write(&cursor_path, serde_json::to_string(&cursor).unwrap()).unwrap();

        let mut secrets = HashMap::new();
        secrets.insert("0xaaa".to_string(), [0x12; 32]);
        let mut block_hashes = HashMap::new();
        block_hashes.insert(106, "0xnew".to_string());
        let source = MockSource {
            latest: 120,
            events: vec![secret_event(106, "0xaaa")],
            secrets,
            block_hashes,
            ..MockSource::default()
        };
        let claimant = MockClaimant::default();
        let relayer = SecretRevealRelayer::new(config(cursor_path.clone()));

        let stats = relayer.run_once(&source, &claimant).await.unwrap();
        assert_eq!(stats.from_block, 106);
        assert_eq!(stats.reveals_claimed, 1);

        let cursor: RelayerCursor =
            serde_json::from_str(&fs::read_to_string(cursor_path).unwrap()).unwrap();
        assert!(cursor
            .processed_event_ids
            .contains("104:0xold:SecretRevealed"));
        assert!(cursor
            .processed_event_ids
            .contains("106:0xaaa:SecretRevealed"));
    }

    #[test]
    fn event_id_requires_transaction_hash() {
        let meta = StarknetEventMeta {
            transaction_hash: "0x0".to_string(),
            block_number: Some(1),
        };
        assert!(event_id("SecretRevealed", &meta, 1).is_err());
    }

    #[test]
    fn traits_are_object_safe_enough_for_shared_claimants() {
        let claimant: Arc<dyn MoneroSecretClaimant> = Arc::new(MockClaimant::default());
        assert_eq!(Arc::strong_count(&claimant), 1);
    }
}
