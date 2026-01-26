use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::types::{SecretRevealedEvent, TokensClaimedEvent};

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct RegistryData {
    pub swaps: HashMap<String, SwapRecord>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SwapRecord {
    pub contract_address: String,
    pub status: SwapStatus,
    pub secret_hash: Option<u32>,
    pub claimable_after: Option<u64>,
    pub revealer: Option<String>,
    pub reveal_tx_hash: Option<String>,
    pub monero_txid: Option<String>,
    pub monero_block_height: Option<u64>,
    pub tokens_claimed_at: Option<u64>,
    pub claimer: Option<String>,
    pub last_update: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum SwapStatus {
    Locked,
    SecretRevealed,
    TokensClaimed,
    RelayerSubmitted { tx_hash: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RegistrySnapshot {
    pub total_swaps: usize,
    pub revealed: usize,
    pub claimed: usize,
    pub last_update: u64,
}

pub struct SwapRegistry {
    path: PathBuf,
    data: RegistryData,
}

impl SwapRegistry {
    pub fn load(path: PathBuf) -> Result<Self> {
        if path.exists() {
            let contents = fs::read_to_string(&path)
                .with_context(|| format!("Failed to read registry file {}", path.display()))?;
            let data: RegistryData = serde_json::from_str(&contents)
                .with_context(|| format!("Failed to parse registry file {}", path.display()))?;
            Ok(Self { path, data })
        } else {
            Ok(Self {
                path,
                data: RegistryData::default(),
            })
        }
    }

    pub fn save(&self) -> Result<()> {
        if let Some(parent) = self.path.parent() {
            if !parent.as_os_str().is_empty() {
                fs::create_dir_all(parent).with_context(|| {
                    format!("Failed to create registry directory {}", parent.display())
                })?;
            }
        }
        let serialized = serde_json::to_string_pretty(&self.data)
            .context("Failed to serialize registry data")?;
        fs::write(&self.path, serialized)
            .with_context(|| format!("Failed to write registry file {}", self.path.display()))?;
        Ok(())
    }

    pub fn record_secret_revealed(
        &mut self,
        event: &SecretRevealedEvent,
        monero_info: Option<(String, u64)>,
    ) {
        let now = now_secs();
        let entry = self
            .data
            .swaps
            .entry(event.contract_address.clone())
            .or_insert_with(|| SwapRecord {
                contract_address: event.contract_address.clone(),
                status: SwapStatus::Locked,
                secret_hash: None,
                claimable_after: None,
                revealer: None,
                reveal_tx_hash: None,
                monero_txid: None,
                monero_block_height: None,
                tokens_claimed_at: None,
                claimer: None,
                last_update: now,
            });

        entry.status = SwapStatus::SecretRevealed;
        entry.secret_hash = Some(event.secret_hash);
        entry.claimable_after = Some(event.claimable_after);
        entry.revealer = Some(event.revealer.clone());
        entry.reveal_tx_hash = Some(event.transaction_hash.clone());
        entry.last_update = now;

        if let Some((txid, height)) = monero_info {
            entry.monero_txid = Some(txid);
            entry.monero_block_height = Some(height);
        }
    }

    pub fn record_tokens_claimed(&mut self, event: &TokensClaimedEvent) {
        let now = now_secs();
        let entry = self
            .data
            .swaps
            .entry(event.contract_address.clone())
            .or_insert_with(|| SwapRecord {
                contract_address: event.contract_address.clone(),
                status: SwapStatus::Locked,
                secret_hash: None,
                claimable_after: None,
                revealer: None,
                reveal_tx_hash: None,
                monero_txid: None,
                monero_block_height: None,
                tokens_claimed_at: None,
                claimer: None,
                last_update: now,
            });

        entry.status = SwapStatus::TokensClaimed;
        entry.tokens_claimed_at = Some(event.claim_timestamp);
        entry.claimer = Some(event.claimer.clone());
        entry.last_update = now;
    }

    pub fn record_relayer_submission(&mut self, contract: &str, tx_hash: &str) {
        let now = now_secs();
        let entry = self
            .data
            .swaps
            .entry(contract.to_string())
            .or_insert_with(|| SwapRecord {
                contract_address: contract.to_string(),
                status: SwapStatus::Locked,
                secret_hash: None,
                claimable_after: None,
                revealer: None,
                reveal_tx_hash: None,
                monero_txid: None,
                monero_block_height: None,
                tokens_claimed_at: None,
                claimer: None,
                last_update: now,
            });

        entry.status = SwapStatus::RelayerSubmitted {
            tx_hash: tx_hash.to_string(),
        };
        entry.last_update = now;
    }

    pub fn snapshot(&self) -> RegistrySnapshot {
        let mut revealed = 0usize;
        let mut claimed = 0usize;
        let mut last_update = 0u64;

        for record in self.data.swaps.values() {
            match record.status {
                SwapStatus::SecretRevealed => revealed += 1,
                SwapStatus::TokensClaimed => claimed += 1,
                _ => {}
            }
            if record.last_update > last_update {
                last_update = record.last_update;
            }
        }

        RegistrySnapshot {
            total_swaps: self.data.swaps.len(),
            revealed,
            claimed,
            last_update,
        }
    }
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn record_updates() {
        let mut registry = SwapRegistry {
            path: PathBuf::from("unused.json"),
            data: RegistryData::default(),
        };

        let reveal_event = SecretRevealedEvent {
            contract_address: "0xabc".to_string(),
            revealer: "0xdef".to_string(),
            secret_hash: 42,
            claimable_after: 100,
            block_number: 1,
            transaction_hash: "0x123".to_string(),
        };

        registry.record_secret_revealed(&reveal_event, Some(("txid".to_string(), 10)));
        let snapshot = registry.snapshot();
        assert_eq!(snapshot.total_swaps, 1);
        assert_eq!(snapshot.revealed, 1);

        let claim_event = TokensClaimedEvent {
            contract_address: "0xabc".to_string(),
            claimer: "0x999".to_string(),
            amount: 7,
            reveal_timestamp: 0,
            claim_timestamp: 123,
        };
        registry.record_tokens_claimed(&claim_event);
        let snapshot = registry.snapshot();
        assert_eq!(snapshot.claimed, 1);
    }
}
