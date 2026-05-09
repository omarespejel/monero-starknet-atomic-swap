//! Starknet read-only integration for AtomicLock event watching.
//!
//! Signed transactions are intentionally handled by sncast/starknet.js tooling.
//! This module is for production-safe JSON-RPC reads: block numbers, paginated
//! event queries, and selector-based AtomicLock event decoding.

use anyhow::{anyhow, Context, Result};
use serde_json::{json, Map, Value};
use tiny_keccak::{Hasher, Keccak};

const EVENT_PAGE_SIZE: u64 = 100;
const MAX_EVENT_PAGES: usize = 100;

/// Starknet RPC client using HTTP JSON-RPC.
pub struct StarknetClient {
    rpc_url: String,
    client: reqwest::Client,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StarknetEventMeta {
    pub transaction_hash: String,
    pub block_number: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AtomicLockEvent {
    ContractDeployed {
        meta: StarknetEventMeta,
        deployer: String,
        depositor: String,
        version: String,
        lock_until: u64,
    },
    Unlocked {
        meta: StarknetEventMeta,
        unlocker: String,
        secret_hash: String,
    },
    Refunded {
        meta: StarknetEventMeta,
        depositor: String,
        amount_low: String,
        amount_high: String,
    },
    SecretRevealed {
        meta: StarknetEventMeta,
        revealer: String,
        secret_hash: String,
        claimable_after: u64,
    },
    TokensClaimed {
        meta: StarknetEventMeta,
        claimer: String,
        amount_low: String,
        amount_high: String,
        reveal_timestamp: u64,
        claim_timestamp: u64,
    },
}

impl StarknetClient {
    pub fn new(rpc_url: String) -> Self {
        Self {
            rpc_url,
            client: reqwest::Client::new(),
        }
    }

    /// Call Starknet JSON-RPC method.
    async fn call(&self, method: &str, params: Value) -> Result<Value> {
        let payload = json!({
            "jsonrpc": "2.0",
            "id": 1,
            "method": method,
            "params": params,
        });

        let response = self
            .client
            .post(&self.rpc_url)
            .json(&payload)
            .send()
            .await
            .context("Failed to send RPC request")?;

        let result: Value = response
            .json()
            .await
            .context("Failed to parse RPC response")?;

        if let Some(error) = result.get("error") {
            anyhow::bail!("RPC error: {}", error);
        }

        Ok(result.get("result").cloned().unwrap_or(result))
    }

    /// Get current block number.
    pub async fn get_block_number(&self) -> Result<u64> {
        let result = self.call("starknet_blockNumber", json!([])).await?;
        parse_u64_value(&result, "block number")
    }

    /// Get all events from a contract starting at `from_block`.
    ///
    /// This follows Starknet RPC pagination and returns raw JSON events for
    /// callers that need custom decoding.
    pub async fn get_events(
        &self,
        contract_address: &str,
        from_block: Option<u64>,
    ) -> Result<Vec<Value>> {
        self.get_events_filtered(contract_address, from_block, None, None)
            .await
    }

    /// Get decoded AtomicLock events from a block range.
    pub async fn get_atomic_lock_events(
        &self,
        contract_address: &str,
        from_block: Option<u64>,
        to_block: Option<u64>,
    ) -> Result<Vec<AtomicLockEvent>> {
        let raw = self
            .get_events_filtered(contract_address, from_block, to_block, None)
            .await?;
        decode_atomic_lock_events(&raw)
    }

    /// Fetch a transaction by hash.
    pub async fn get_transaction_by_hash(&self, tx_hash: &str) -> Result<Value> {
        self.call(
            "starknet_getTransactionByHash",
            json!({ "transaction_hash": tx_hash }),
        )
        .await
    }

    /// Extract the full 32-byte `reveal_secret` argument from a transaction.
    pub async fn get_reveal_secret_from_transaction(
        &self,
        tx_hash: &str,
        contract_address: &str,
    ) -> Result<Option<[u8; 32]>> {
        let transaction = self.get_transaction_by_hash(tx_hash).await?;
        extract_reveal_secret_from_invoke_transaction(&transaction, contract_address)
    }

    async fn get_events_filtered(
        &self,
        contract_address: &str,
        from_block: Option<u64>,
        to_block: Option<u64>,
        first_key: Option<&str>,
    ) -> Result<Vec<Value>> {
        let mut continuation_token: Option<String> = None;
        let mut events = Vec::new();

        for _ in 0..MAX_EVENT_PAGES {
            let mut filter = Map::new();
            filter.insert("address".to_string(), json!(contract_address));
            filter.insert("chunk_size".to_string(), json!(EVENT_PAGE_SIZE));

            if let Some(from) = from_block {
                filter.insert("from_block".to_string(), block_id_from_number(from));
            }

            match to_block {
                Some(to) => {
                    filter.insert("to_block".to_string(), block_id_from_number(to));
                }
                None => {
                    filter.insert("to_block".to_string(), json!("latest"));
                }
            }

            if let Some(key) = first_key {
                filter.insert("keys".to_string(), json!([[normalize_hex(key)]]));
            }

            if let Some(token) = &continuation_token {
                filter.insert("continuation_token".to_string(), json!(token));
            }

            let result = self
                .call(
                    "starknet_getEvents",
                    json!({ "filter": Value::Object(filter) }),
                )
                .await?;

            if let Some(array) = result.as_array() {
                events.extend(array.iter().cloned());
                break;
            }

            let page_events = result
                .get("events")
                .and_then(Value::as_array)
                .ok_or_else(|| anyhow!("Invalid starknet_getEvents response: {}", result))?;
            events.extend(page_events.iter().cloned());

            continuation_token = result.get("continuation_token").and_then(|token| {
                if token.is_null() {
                    None
                } else if let Some(token) = token.as_str() {
                    Some(token.to_string())
                } else {
                    Some(token.to_string())
                }
            });

            if continuation_token.is_none() {
                break;
            }
        }

        if continuation_token.is_some() {
            anyhow::bail!(
                "Event pagination exceeded {} pages; narrow the block range",
                MAX_EVENT_PAGES
            );
        }

        Ok(events)
    }

    /// Call contract function (simplified - requires account signing in production).
    pub async fn call_contract(
        &self,
        contract_address: &str,
        function: &str,
        calldata: Vec<String>,
    ) -> Result<Value> {
        let _ = (contract_address, function, calldata);
        anyhow::bail!(
            "Contract calls require account signing - use sncast or starknet.js account tooling"
        );
    }
}

/// Watch for AtomicLock reveal/unlock events and return the observed hash word.
pub async fn watch_unlocked_events(
    client: &StarknetClient,
    contract_address: &str,
    poll_interval_secs: u64,
) -> Result<String> {
    println!(
        "Watching AtomicLock reveal/unlock events from contract: {}",
        contract_address
    );

    let mut next_block = client.get_block_number().await?;

    loop {
        tokio::time::sleep(tokio::time::Duration::from_secs(poll_interval_secs)).await;

        let current_block = client.get_block_number().await?;
        if current_block < next_block {
            continue;
        }

        let events = client
            .get_atomic_lock_events(contract_address, Some(next_block), Some(current_block))
            .await
            .context("Failed to fetch AtomicLock events")?;

        for event in events {
            match event {
                AtomicLockEvent::Unlocked {
                    meta,
                    unlocker,
                    secret_hash,
                } => {
                    let secret_hex = client
                        .get_reveal_secret_from_transaction(
                            &meta.transaction_hash,
                            contract_address,
                        )
                        .await?
                        .map(|secret| format!("0x{}", hex::encode(secret)));
                    println!(
                        "Unlocked event detected: tx={}, block={:?}, unlocker={}, secret_hash={}, secret={}",
                        meta.transaction_hash,
                        meta.block_number,
                        unlocker,
                        secret_hash,
                        secret_hex.as_deref().unwrap_or("<not found in calldata>")
                    );
                    return Ok(secret_hash);
                }
                AtomicLockEvent::SecretRevealed {
                    meta,
                    revealer,
                    secret_hash,
                    claimable_after,
                } => {
                    let secret_hex = client
                        .get_reveal_secret_from_transaction(
                            &meta.transaction_hash,
                            contract_address,
                        )
                        .await?
                        .map(|secret| format!("0x{}", hex::encode(secret)));
                    println!(
                        "SecretRevealed event detected: tx={}, block={:?}, revealer={}, secret_hash={}, claimable_after={}, secret={}",
                        meta.transaction_hash,
                        meta.block_number,
                        revealer,
                        secret_hash,
                        claimable_after,
                        secret_hex.as_deref().unwrap_or("<not found in calldata>")
                    );
                    return Ok(secret_hash);
                }
                _ => {}
            }
        }

        next_block = current_block.saturating_add(1);
    }
}

pub fn decode_atomic_lock_events(raw_events: &[Value]) -> Result<Vec<AtomicLockEvent>> {
    raw_events
        .iter()
        .filter_map(|event| match decode_atomic_lock_event(event) {
            Ok(Some(decoded)) => Some(Ok(decoded)),
            Ok(None) => None,
            Err(err) => Some(Err(err)),
        })
        .collect()
}

pub fn decode_atomic_lock_event(event: &Value) -> Result<Option<AtomicLockEvent>> {
    let keys = event_field_array(event, "keys")?;
    if keys.is_empty() {
        return Ok(None);
    }

    let selector = normalize_hex(&keys[0]);
    let data = event_field_array(event, "data")?;
    let meta = event_meta(event)?;

    if selector == starknet_selector("ContractDeployed") {
        require_len(&keys, 3, "ContractDeployed keys")?;
        require_len(&data, 2, "ContractDeployed data")?;
        return Ok(Some(AtomicLockEvent::ContractDeployed {
            meta,
            deployer: normalize_hex(&keys[1]),
            depositor: normalize_hex(&keys[2]),
            version: normalize_hex(&data[0]),
            lock_until: parse_u64_str(&data[1], "ContractDeployed.lock_until")?,
        }));
    }

    if selector == starknet_selector("Unlocked") {
        require_len(&keys, 2, "Unlocked keys")?;
        require_len(&data, 1, "Unlocked data")?;
        return Ok(Some(AtomicLockEvent::Unlocked {
            meta,
            unlocker: normalize_hex(&keys[1]),
            secret_hash: normalize_hex(&data[0]),
        }));
    }

    if selector == starknet_selector("Refunded") {
        require_len(&keys, 2, "Refunded keys")?;
        require_len(&data, 2, "Refunded data")?;
        return Ok(Some(AtomicLockEvent::Refunded {
            meta,
            depositor: normalize_hex(&keys[1]),
            amount_low: normalize_hex(&data[0]),
            amount_high: normalize_hex(&data[1]),
        }));
    }

    if selector == starknet_selector("SecretRevealed") {
        require_len(&keys, 2, "SecretRevealed keys")?;
        require_len(&data, 2, "SecretRevealed data")?;
        return Ok(Some(AtomicLockEvent::SecretRevealed {
            meta,
            revealer: normalize_hex(&keys[1]),
            secret_hash: normalize_hex(&data[0]),
            claimable_after: parse_u64_str(&data[1], "SecretRevealed.claimable_after")?,
        }));
    }

    if selector == starknet_selector("TokensClaimed") {
        require_len(&keys, 2, "TokensClaimed keys")?;
        require_len(&data, 4, "TokensClaimed data")?;
        return Ok(Some(AtomicLockEvent::TokensClaimed {
            meta,
            claimer: normalize_hex(&keys[1]),
            amount_low: normalize_hex(&data[0]),
            amount_high: normalize_hex(&data[1]),
            reveal_timestamp: parse_u64_str(&data[2], "TokensClaimed.reveal_timestamp")?,
            claim_timestamp: parse_u64_str(&data[3], "TokensClaimed.claim_timestamp")?,
        }));
    }

    Ok(None)
}

pub fn extract_reveal_secret_from_invoke_transaction(
    transaction: &Value,
    contract_address: &str,
) -> Result<Option<[u8; 32]>> {
    let calldata = event_field_array(transaction, "calldata")?;

    if let Some(secret) = extract_reveal_secret_from_simple_account_calldata(
        &calldata,
        contract_address,
        &starknet_selector("reveal_secret"),
    )? {
        return Ok(Some(secret));
    }

    extract_reveal_secret_from_offset_account_calldata(
        &calldata,
        contract_address,
        &starknet_selector("reveal_secret"),
    )
}

fn extract_reveal_secret_from_simple_account_calldata(
    calldata: &[String],
    contract_address: &str,
    reveal_selector: &str,
) -> Result<Option<[u8; 32]>> {
    if calldata.is_empty() {
        return Ok(None);
    }

    let call_count = parse_usize_str(&calldata[0], "account calldata call count")?;
    let target = normalize_hex(contract_address);
    let mut index = 1usize;

    for _ in 0..call_count {
        if index + 3 > calldata.len() {
            anyhow::bail!("Malformed account calldata: truncated call descriptor");
        }

        let to = normalize_hex(&calldata[index]);
        let selector = normalize_hex(&calldata[index + 1]);
        let data_len = parse_usize_str(&calldata[index + 2], "call data length")?;
        let data_start = index + 3;
        let data_end = data_start
            .checked_add(data_len)
            .ok_or_else(|| anyhow!("call data length overflow"))?;

        if data_end > calldata.len() {
            return Ok(None);
        }

        if to == target && selector == normalize_hex(reveal_selector) {
            if data_len < 3 {
                return Ok(None);
            }
            return decode_reveal_secret_calldata(&calldata[data_start..data_end]).map(Some);
        }

        index = data_end;
    }

    Ok(None)
}

fn extract_reveal_secret_from_offset_account_calldata(
    calldata: &[String],
    contract_address: &str,
    reveal_selector: &str,
) -> Result<Option<[u8; 32]>> {
    if calldata.is_empty() {
        return Ok(None);
    }

    let call_count = parse_usize_str(&calldata[0], "account calldata call count")?;
    let descriptor_start = 1usize;
    let descriptor_len = call_count
        .checked_mul(4)
        .ok_or_else(|| anyhow!("call descriptor length overflow"))?;
    let descriptor_end = descriptor_start
        .checked_add(descriptor_len)
        .ok_or_else(|| anyhow!("call descriptor length overflow"))?;

    if descriptor_end >= calldata.len() {
        return Ok(None);
    }

    let flattened_len = parse_usize_str(&calldata[descriptor_end], "flattened calldata length")?;
    let flattened_start = descriptor_end + 1;
    let flattened_end = flattened_start
        .checked_add(flattened_len)
        .ok_or_else(|| anyhow!("flattened calldata length overflow"))?;

    if flattened_end > calldata.len() {
        return Ok(None);
    }

    let target = normalize_hex(contract_address);
    let reveal_selector = normalize_hex(reveal_selector);

    for call_index in 0..call_count {
        let descriptor = descriptor_start + call_index * 4;
        let to = normalize_hex(&calldata[descriptor]);
        let selector = normalize_hex(&calldata[descriptor + 1]);
        let data_offset = parse_usize_str(&calldata[descriptor + 2], "call data offset")?;
        let data_len = parse_usize_str(&calldata[descriptor + 3], "call data length")?;
        let data_start = flattened_start
            .checked_add(data_offset)
            .ok_or_else(|| anyhow!("call data offset overflow"))?;
        let data_end = data_start
            .checked_add(data_len)
            .ok_or_else(|| anyhow!("call data length overflow"))?;

        if data_end > flattened_end {
            anyhow::bail!("Malformed account calldata: call data outside flattened data");
        }

        if to == target && selector == reveal_selector {
            return decode_reveal_secret_calldata(&calldata[data_start..data_end]).map(Some);
        }
    }

    Ok(None)
}

fn decode_reveal_secret_calldata(calldata: &[String]) -> Result<[u8; 32]> {
    let bytes = decode_cairo_byte_array(calldata)?;
    if bytes.len() != 32 {
        anyhow::bail!(
            "reveal_secret ByteArray must decode to 32 bytes, got {}",
            bytes.len()
        );
    }

    let mut secret = [0u8; 32];
    secret.copy_from_slice(&bytes);
    Ok(secret)
}

fn decode_cairo_byte_array(calldata: &[String]) -> Result<Vec<u8>> {
    if calldata.len() < 3 {
        anyhow::bail!("ByteArray calldata is too short");
    }

    let full_words = parse_usize_str(&calldata[0], "ByteArray full word count")?;
    let expected_len = 1usize
        .checked_add(full_words)
        .and_then(|value| value.checked_add(2))
        .ok_or_else(|| anyhow!("ByteArray calldata length overflow"))?;

    if calldata.len() != expected_len {
        anyhow::bail!(
            "ByteArray calldata length mismatch: expected {}, got {}",
            expected_len,
            calldata.len()
        );
    }

    let mut bytes = Vec::with_capacity(full_words * 31 + 30);
    for word in &calldata[1..=full_words] {
        bytes.extend(felt_to_fixed_bytes(word, 31)?);
    }

    let pending_word = &calldata[1 + full_words];
    let pending_len = parse_usize_str(&calldata[2 + full_words], "ByteArray pending length")?;
    if pending_len > 30 {
        anyhow::bail!(
            "ByteArray pending length must be <= 30, got {}",
            pending_len
        );
    }
    bytes.extend(felt_to_fixed_bytes(pending_word, pending_len)?);

    Ok(bytes)
}

fn felt_to_fixed_bytes(felt: &str, width: usize) -> Result<Vec<u8>> {
    if width == 0 {
        if normalize_hex(felt) != "0x0" {
            anyhow::bail!("non-zero felt cannot fit into zero bytes");
        }
        return Ok(Vec::new());
    }

    let trimmed = felt.trim();
    let mut hex_value = trimmed
        .strip_prefix("0x")
        .or_else(|| trimmed.strip_prefix("0X"))
        .unwrap_or(trimmed)
        .to_string();

    if hex_value.len() % 2 == 1 {
        hex_value.insert(0, '0');
    }

    let decoded = if hex_value.is_empty() {
        Vec::new()
    } else {
        hex::decode(&hex_value).with_context(|| format!("Invalid felt hex: {}", felt))?
    };

    if decoded.len() > width {
        anyhow::bail!("felt {} exceeds {} bytes", felt, width);
    }

    let mut out = vec![0u8; width];
    let start = width - decoded.len();
    out[start..].copy_from_slice(&decoded);
    Ok(out)
}

fn event_meta(event: &Value) -> Result<StarknetEventMeta> {
    let transaction_hash = event
        .get("transaction_hash")
        .and_then(Value::as_str)
        .map(normalize_hex)
        .unwrap_or_else(|| "0x0".to_string());

    let block_number = match event.get("block_number") {
        Some(value) if !value.is_null() => Some(parse_u64_value(value, "event.block_number")?),
        _ => None,
    };

    Ok(StarknetEventMeta {
        transaction_hash,
        block_number,
    })
}

fn event_field_array(event: &Value, field: &str) -> Result<Vec<String>> {
    event
        .get(field)
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("Event missing array field `{}`: {}", field, event))?
        .iter()
        .map(|value| {
            value
                .as_str()
                .map(str::to_string)
                .ok_or_else(|| anyhow!("Event field `{}` contains non-string felt", field))
        })
        .collect()
}

fn require_len(values: &[String], min_len: usize, label: &str) -> Result<()> {
    if values.len() < min_len {
        anyhow::bail!(
            "{} expected at least {} felts, got {}",
            label,
            min_len,
            values.len()
        );
    }
    Ok(())
}

fn block_id_from_number(block_number: u64) -> Value {
    json!({ "block_number": block_number })
}

fn starknet_selector(name: &str) -> String {
    let mut output = [0u8; 32];
    let mut hasher = Keccak::v256();
    hasher.update(name.as_bytes());
    hasher.finalize(&mut output);
    output[0] &= 0x03;
    normalize_hex(&format!("0x{}", hex::encode(output)))
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

fn parse_u64_value(value: &Value, label: &str) -> Result<u64> {
    if let Some(number) = value.as_u64() {
        return Ok(number);
    }
    if let Some(text) = value.as_str() {
        return parse_u64_str(text, label);
    }
    Err(anyhow!("Invalid {} format: {}", label, value))
}

fn parse_u64_str(value: &str, label: &str) -> Result<u64> {
    let trimmed = value.trim();
    if let Some(hex) = trimmed
        .strip_prefix("0x")
        .or_else(|| trimmed.strip_prefix("0X"))
    {
        u64::from_str_radix(if hex.is_empty() { "0" } else { hex }, 16)
            .with_context(|| format!("Failed to parse {} as hex u64", label))
    } else {
        trimmed
            .parse::<u64>()
            .with_context(|| format!("Failed to parse {} as decimal u64", label))
    }
}

fn parse_usize_str(value: &str, label: &str) -> Result<usize> {
    let parsed = parse_u64_str(value, label)?;
    usize::try_from(parsed).with_context(|| format!("{} does not fit in usize", label))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn selector_is_starknet_keccak_normalized() {
        assert_eq!(
            starknet_selector("SecretRevealed"),
            normalize_hex(&starknet_selector("SecretRevealed"))
        );
        assert_ne!(
            starknet_selector("SecretRevealed"),
            starknet_selector("TokensClaimed")
        );
    }

    #[test]
    fn decodes_secret_revealed_event() {
        let raw = json!({
            "transaction_hash": "0xabc",
            "block_number": "0x2a",
            "keys": [starknet_selector("SecretRevealed"), "0x000123"],
            "data": ["0x12", "0x69fe8c2c"]
        });

        let decoded = decode_atomic_lock_event(&raw).unwrap().unwrap();
        assert_eq!(
            decoded,
            AtomicLockEvent::SecretRevealed {
                meta: StarknetEventMeta {
                    transaction_hash: "0xabc".to_string(),
                    block_number: Some(42),
                },
                revealer: "0x123".to_string(),
                secret_hash: "0x12".to_string(),
                claimable_after: 1_778_289_708,
            }
        );
    }

    #[test]
    fn decodes_tokens_claimed_event() {
        let raw = json!({
            "transaction_hash": "0xdef",
            "block_number": 43,
            "keys": [starknet_selector("TokensClaimed"), "0x456"],
            "data": ["0x5af3107a4000", "0x0", "0x10", "0x20"]
        });

        let decoded = decode_atomic_lock_event(&raw).unwrap().unwrap();
        assert_eq!(
            decoded,
            AtomicLockEvent::TokensClaimed {
                meta: StarknetEventMeta {
                    transaction_hash: "0xdef".to_string(),
                    block_number: Some(43),
                },
                claimer: "0x456".to_string(),
                amount_low: "0x5af3107a4000".to_string(),
                amount_high: "0x0".to_string(),
                reveal_timestamp: 16,
                claim_timestamp: 32,
            }
        );
    }

    #[test]
    fn extracts_reveal_secret_from_sncast_calldata() {
        let transaction = json!({
            "calldata": [
                "0x1",
                "0x56874c6da7e5d485e337769d2267fc6a024a57df85b529d08f453e86b6a40aa",
                starknet_selector("reveal_secret"),
                "0x4",
                "0x1",
                "0x12121212121212121212121212121212121212121212121212121212121212",
                "0x12",
                "0x1"
            ]
        });

        let secret = extract_reveal_secret_from_invoke_transaction(
            &transaction,
            "0x056874c6da7e5d485e337769d2267fc6a024a57df85b529d08f453e86b6a40aa",
        )
        .unwrap()
        .unwrap();
        assert_eq!(secret, [0x12u8; 32]);
    }

    #[test]
    fn extracts_reveal_secret_from_offset_account_calldata() {
        let transaction = json!({
            "calldata": [
                "0x1",
                "0xabc",
                starknet_selector("reveal_secret"),
                "0x0",
                "0x4",
                "0x4",
                "0x1",
                "0x12121212121212121212121212121212121212121212121212121212121212",
                "0x12",
                "0x1"
            ]
        });

        let secret = extract_reveal_secret_from_invoke_transaction(&transaction, "0xabc")
            .unwrap()
            .unwrap();
        assert_eq!(secret, [0x12u8; 32]);
    }
}
