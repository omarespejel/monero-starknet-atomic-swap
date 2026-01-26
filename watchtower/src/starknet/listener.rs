use anyhow::{anyhow, Context, Result};
use lazy_static::lazy_static;
use serde_json::{json, Value};
use sha3::{Digest, Keccak256};
use std::convert::TryInto;
use tokio::sync::mpsc;
use tracing::{error, info, warn};

use crate::types::{SecretRevealedEvent, TokensClaimedEvent};

/// Starknet event listener for AtomicLock contracts (JSON-RPC, macOS compatible)
pub struct StarknetListener {
    rpc_url: String,
    watched_contracts: Vec<String>,
    event_tx: mpsc::Sender<SwapEvent>,
    client: reqwest::Client,
}

pub enum SwapEvent {
    SecretRevealed(SecretRevealedEvent),
    TokensClaimed(TokensClaimedEvent),
}

lazy_static! {
    /// Selector for SecretRevealed(revealer, secret_hash, claimable_after)
    pub static ref SECRET_REVEALED_SELECTOR: [u8; 32] = starknet_keccak_bytes(b"SecretRevealed");
    /// Selector for TokensClaimed(claimer, amount, reveal_timestamp, claim_timestamp)
    pub static ref TOKENS_CLAIMED_SELECTOR: [u8; 32] = starknet_keccak_bytes(b"TokensClaimed");
    /// Selector for Unlocked(unlocker, secret_hash) - backward compatibility
    pub static ref UNLOCKED_SELECTOR: [u8; 32] = starknet_keccak_bytes(b"Unlocked");
}

impl StarknetListener {
    pub fn new(
        rpc_url: &str,
        watched_contracts: Vec<String>,
        event_tx: mpsc::Sender<SwapEvent>,
    ) -> Result<Self> {
        Ok(Self {
            rpc_url: rpc_url.to_string(),
            watched_contracts,
            event_tx,
            client: reqwest::Client::new(),
        })
    }

    /// Start listening for events
    pub async fn run(&self) -> Result<()> {
        info!("Starting Starknet event listener");

        let mut last_block = self.get_latest_block().await?;

        loop {
            tokio::time::sleep(tokio::time::Duration::from_secs(10)).await;

            let current_block = self.get_latest_block().await?;
            if current_block > last_block {
                for block_num in (last_block + 1)..=current_block {
                    if let Err(e) = self.process_block(block_num).await {
                        error!("Failed to process block {}: {}", block_num, e);
                    }
                }
                last_block = current_block;
            }
        }
    }

    async fn get_latest_block(&self) -> Result<u64> {
        let result = self
            .rpc_call("starknet_getBlockWithTxHashes", json!({ "block_id": "latest" }))
            .await?;
        result["block_number"]
            .as_u64()
            .context("Invalid block_number in response")
    }

    async fn process_block(&self, block_number: u64) -> Result<()> {
        info!("Processing block {}", block_number);

        for contract in &self.watched_contracts {
            self.process_contract_block(contract, block_number).await?;
        }

        Ok(())
    }

    async fn process_contract_block(&self, contract: &str, block_number: u64) -> Result<()> {
        let mut continuation: Option<String> = None;
        loop {
            let filter = json!({
                "from_block": { "block_number": block_number },
                "to_block": { "block_number": block_number },
                "address": contract,
                "keys": Value::Null
            });
            let params = json!({
                "filter": filter,
                "continuation_token": continuation,
                "chunk_size": 100
            });

            let result = self.rpc_call("starknet_getEvents", params).await?;
            let events = result
                .get("events")
                .and_then(|v| v.as_array())
                .ok_or_else(|| anyhow!("Invalid events response"))?;

            for event in events {
                self.handle_event(event, block_number).await?;
            }

            continuation = result
                .get("continuation_token")
                .and_then(|v| v.as_str())
                .map(|s| s.to_string());

            if continuation.is_none() {
                break;
            }
        }

        Ok(())
    }

    async fn handle_event(&self, event: &Value, block_number: u64) -> Result<()> {
        let keys = event
            .get("keys")
            .and_then(|v| v.as_array())
            .ok_or_else(|| anyhow!("Event keys missing"))?;
        let data = event
            .get("data")
            .and_then(|v| v.as_array())
            .ok_or_else(|| anyhow!("Event data missing"))?;

        let selector_hex = keys.get(0).and_then(|v| v.as_str()).unwrap_or("0x0");
        let selector_bytes = felt_bytes_from_hex(selector_hex)?;

        if selector_bytes == *SECRET_REVEALED_SELECTOR {
            let revealer = keys.get(1).and_then(|v| v.as_str()).unwrap_or("0x0");
            let secret_hash = data
                .get(0)
                .and_then(|v| v.as_str())
                .map(felt_u32_from_hex)
                .transpose()?
                .unwrap_or(0);
            let claimable_after = data
                .get(1)
                .and_then(|v| v.as_str())
                .map(felt_u64_from_hex)
                .transpose()?
                .unwrap_or(0);

            let evt = SecretRevealedEvent {
                contract_address: normalize_hex(event.get("from_address").and_then(|v| v.as_str()).unwrap_or("0x0")),
                revealer: normalize_hex(revealer),
                secret_hash,
                claimable_after,
                block_number,
                transaction_hash: normalize_hex(event.get("transaction_hash").and_then(|v| v.as_str()).unwrap_or("0x0")),
            };

            info!(
                "SecretRevealed event detected: contract {}, claimable after {}",
                evt.contract_address, evt.claimable_after
            );

            self.event_tx.send(SwapEvent::SecretRevealed(evt)).await?;
        } else if selector_bytes == *TOKENS_CLAIMED_SELECTOR {
            let claimer = keys.get(1).and_then(|v| v.as_str()).unwrap_or("0x0");
            let amount_low = data
                .get(0)
                .and_then(|v| v.as_str())
                .map(felt_u128_from_hex)
                .transpose()?
                .unwrap_or(0);
            let reveal_timestamp = data
                .get(2)
                .and_then(|v| v.as_str())
                .map(felt_u64_from_hex)
                .transpose()?
                .unwrap_or(0);
            let claim_timestamp = data
                .get(3)
                .and_then(|v| v.as_str())
                .map(felt_u64_from_hex)
                .transpose()?
                .unwrap_or(0);

            let evt = TokensClaimedEvent {
                contract_address: normalize_hex(event.get("from_address").and_then(|v| v.as_str()).unwrap_or("0x0")),
                claimer: normalize_hex(claimer),
                amount: amount_low,
                reveal_timestamp,
                claim_timestamp,
            };

            info!(
                "TokensClaimed event detected: contract {}, amount {}",
                evt.contract_address, evt.amount
            );

            self.event_tx.send(SwapEvent::TokensClaimed(evt)).await?;
        } else if selector_bytes == *UNLOCKED_SELECTOR {
            warn!("Unlocked event detected (legacy path).");
        }

        Ok(())
    }

    async fn rpc_call(&self, method: &str, params: Value) -> Result<Value> {
        let payload = json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        });
        let response: Value = self
            .client
            .post(&self.rpc_url)
            .json(&payload)
            .send()
            .await
            .context("RPC request failed")?
            .json()
            .await
            .context("Failed to parse RPC response")?;

        if let Some(error) = response.get("error") {
            return Err(anyhow!("RPC error: {}", error));
        }

        Ok(response["result"].clone())
    }
}

fn starknet_keccak_bytes(input: &[u8]) -> [u8; 32] {
    let mut hasher = Keccak256::new();
    hasher.update(input);
    let mut hash = [0u8; 32];
    hash.copy_from_slice(&hasher.finalize());
    hash[0] &= 0x07; // keep 251 bits
    hash
}

fn normalize_hex(value: &str) -> String {
    let trimmed = value.trim_start_matches("0x");
    format!("0x{}", trimmed.to_lowercase())
}

fn felt_bytes_from_hex(hex_str: &str) -> Result<[u8; 32]> {
    let trimmed = hex_str.trim_start_matches("0x");
    let bytes = hex::decode(trimmed).context("Invalid hex string")?;
    if bytes.len() > 32 {
        return Err(anyhow!("Hex value too large for felt"));
    }
    let mut out = [0u8; 32];
    out[32 - bytes.len()..].copy_from_slice(&bytes);
    Ok(out)
}

fn felt_u32_from_hex(hex_str: &str) -> Result<u32> {
    let bytes = felt_bytes_from_hex(hex_str)?;
    Ok(u32::from_be_bytes(
        bytes[28..32].try_into().context("u32 slice")?,
    ))
}

fn felt_u64_from_hex(hex_str: &str) -> Result<u64> {
    let bytes = felt_bytes_from_hex(hex_str)?;
    Ok(u64::from_be_bytes(
        bytes[24..32].try_into().context("u64 slice")?,
    ))
}

fn felt_u128_from_hex(hex_str: &str) -> Result<u128> {
    let bytes = felt_bytes_from_hex(hex_str)?;
    Ok(u128::from_be_bytes(
        bytes[16..32].try_into().context("u128 slice")?,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_hex_adds_prefix() {
        assert_eq!(normalize_hex("abc"), "0xabc");
        assert_eq!(normalize_hex("0xABC"), "0xabc");
    }

    #[test]
    fn felt_u64_parses_low_bytes() {
        let value = felt_u64_from_hex("0x2a").unwrap();
        assert_eq!(value, 42);
    }

    #[test]
    fn keccak_selector_is_251_bits() {
        let selector = starknet_keccak_bytes(b"SecretRevealed");
        assert_eq!(selector.len(), 32);
        // top 3 bits must be zero after mask
        assert_eq!(selector[0] & 0xF8, 0);
    }
}

