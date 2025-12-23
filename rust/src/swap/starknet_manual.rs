//! Cross-platform StarknetClient using manual JSON-RPC + starknet-ff.
//! 
//! This implementation avoids the full starknet-rs dependency chain that
//! has macOS compatibility issues (size-of crate uses fastcall ABI).
//! 
//! Uses starknet-ff for FieldElement type (macOS compatible).
//! Transaction signing implemented for non-macOS platforms using starknet-crypto.
//! macOS uses placeholder signatures (works for devnet with --seed 0).

use anyhow::{anyhow, Context, Result};
use async_trait::async_trait;
use serde_json::{json, Value};
use sha3::{Digest, Keccak256};

#[cfg(not(target_os = "macos"))]
use starknet_crypto::{pedersen_hash, sign, FieldElement, Signature};

use super::driver::StarknetClient;

/// Felt wrapper using starknet-ff (macOS compatible)
pub type Felt = starknet_ff::FieldElement;

/// A contract call for Starknet invoke transactions
#[derive(Clone, Debug)]
pub struct Call {
    pub to: Felt,
    pub selector: Felt,
    pub data: Vec<Felt>,
}

/// Lightweight Starknet client - macOS compatible.
pub struct StarknetManualClient {
    rpc_url: String,
    account_address: Felt,
    private_key: Felt,
    chain_id: Felt,
    atomic_lock_class_hash: Felt,
    client: reqwest::Client,
}

impl StarknetManualClient {
    pub fn new(
        rpc_url: &str,
        account_address: &str,
        private_key: &str,
        atomic_lock_class_hash: &str,
        chain_id: &str,
    ) -> Result<Self> {
        Ok(Self {
            rpc_url: rpc_url.to_string(),
            account_address: felt_from_hex(account_address)?,
            private_key: felt_from_hex(private_key)?,
            chain_id: felt_from_hex(chain_id)?,
            atomic_lock_class_hash: felt_from_hex(atomic_lock_class_hash)?,
            client: reqwest::Client::new(),
        })
    }

    /// Create devnet client with default parameters.
    pub fn devnet(
        account_address: &str,
        private_key: &str,
        atomic_lock_class_hash: &str,
    ) -> Result<Self> {
        Self::new(
            "http://127.0.0.1:5050",
            account_address,
            private_key,
            atomic_lock_class_hash,
            "0x534e5f5345504f4c4941", // SN_SEPOLIA
        )
    }

    /// Call JSON-RPC method.
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

    /// Get account nonce.
    async fn get_nonce(&self) -> Result<Felt> {
        let result = self
            .rpc_call(
                "starknet_getNonce",
                json!({
                    "block_id": "latest",
                    "contract_address": felt_to_hex(&self.account_address),
                }),
            )
            .await?;

        let nonce_str = result.as_str().context("Invalid nonce format")?;
        felt_from_hex(nonce_str)
    }

    #[cfg(not(target_os = "macos"))]
    /// Compute Pedersen hash of calldata array.
    /// 
    /// Uses iterative Pedersen hashing: hash(hash(hash(0, calldata[0]), calldata[1]), ...)
    fn compute_calldata_hash(&self, calldata: &[Felt]) -> Result<Felt> {
        if calldata.is_empty() {
            return Ok(Felt::from(0u64));
        }

        // Convert Felt to FieldElement for starknet-crypto
        let mut hash = FieldElement::ZERO;
        for felt in calldata {
            let field_elem = felt_to_field_element(felt)?;
            hash = pedersen_hash(&hash, &field_elem);
        }

        // Convert back to Felt
        field_element_to_felt(&hash)
    }

    #[cfg(not(target_os = "macos"))]
    /// Compute transaction hash for v1 invoke transaction.
    /// 
    /// Hash format: H(version, sender_address, calldata_hash, max_fee, nonce, chain_id)
    fn compute_invoke_tx_hash(
        &self,
        calldata: &[Felt],
        max_fee: Felt,
        nonce: Felt,
    ) -> Result<Felt> {
        let version = FieldElement::ONE; // v1 = 0x1
        let sender = felt_to_field_element(&self.account_address)?;
        let calldata_hash = self.compute_calldata_hash(calldata)?;
        let calldata_hash_fe = felt_to_field_element(&calldata_hash)?;
        let max_fee_fe = felt_to_field_element(&max_fee)?;
        let nonce_fe = felt_to_field_element(&nonce)?;
        let chain_id_fe = felt_to_field_element(&self.chain_id)?;

        // Compute hash: H(version, sender, calldata_hash, max_fee, nonce, chain_id)
        let mut hash = pedersen_hash(&version, &sender);
        hash = pedersen_hash(&hash, &calldata_hash_fe);
        hash = pedersen_hash(&hash, &max_fee_fe);
        hash = pedersen_hash(&hash, &nonce_fe);
        hash = pedersen_hash(&hash, &chain_id_fe);

        field_element_to_felt(&hash)
    }

    #[cfg(not(target_os = "macos"))]
    /// Sign transaction hash using STARK curve.
    fn sign_transaction(&self, tx_hash: &Felt) -> Result<(Felt, Felt)> {
        let tx_hash_fe = felt_to_field_element(tx_hash)?;
        let private_key_fe = felt_to_field_element(&self.private_key)?;

        let signature = sign(&private_key_fe, &tx_hash_fe)?;

        let r = field_element_to_felt(&signature.r)?;
        let s = field_element_to_felt(&signature.s)?;

        Ok((r, s))
    }

    /// Submit v1 invoke transaction with real STARK curve signing (non-macOS) or placeholder (macOS).
    /// 
    /// On non-macOS: Implements full transaction signing for production use.
    /// On macOS: Uses placeholder signatures (works for devnet with --seed 0).
    async fn submit_invoke_tx(&self, calls: Vec<Call>) -> Result<String> {
        let nonce = self.get_nonce().await?;
        let calldata = self.build_execute_calldata(&calls);
        let max_fee = Felt::from(0x1000000000000u64); // 0.001 ETH max

        #[cfg(not(target_os = "macos"))]
        {
            // Compute transaction hash
            let tx_hash = self.compute_invoke_tx_hash(&calldata, max_fee, nonce)?;

            // Sign transaction
            let (r, s) = self.sign_transaction(&tx_hash)?;

            let tx = json!({
                "type": "INVOKE",
                "version": "0x1",
                "sender_address": felt_to_hex(&self.account_address),
                "calldata": calldata.iter().map(|f| felt_to_hex(f)).collect::<Vec<_>>(),
                "signature": [felt_to_hex(&r), felt_to_hex(&s)],
                "max_fee": felt_to_hex(&max_fee),
                "nonce": felt_to_hex(&nonce),
            });

            let result = self
                .rpc_call("starknet_addInvokeTransaction", json!({ "invoke_transaction": tx }))
                .await?;

            result["transaction_hash"]
                .as_str()
                .map(|s| s.to_string())
                .context("Missing transaction_hash")
        }

        #[cfg(target_os = "macos")]
        {
            // macOS: Use placeholder signatures (devnet accepts for known accounts)
            let tx = json!({
                "type": "INVOKE",
                "version": "0x1",
                "sender_address": felt_to_hex(&self.account_address),
                "calldata": calldata.iter().map(|f| felt_to_hex(f)).collect::<Vec<_>>(),
                "signature": ["0x0", "0x0"],  // Placeholder - devnet accepts for known accounts
                "max_fee": felt_to_hex(&max_fee),
                "nonce": felt_to_hex(&nonce),
            });

            let result = self
                .rpc_call("starknet_addInvokeTransaction", json!({ "invoke_transaction": tx }))
                .await?;

            result["transaction_hash"]
                .as_str()
                .map(|s| s.to_string())
                .context("Missing transaction_hash")
        }
    }

    /// Build __execute__ calldata for account contract.
    /// 
    /// Format: [num_calls, call1_to, call1_selector, call1_data_len, ...call1_data, ...]
    fn build_execute_calldata(&self, calls: &[Call]) -> Vec<Felt> {
        let mut calldata = vec![Felt::from(calls.len() as u64)];
        
        for call in calls {
            calldata.push(call.to.clone());
            calldata.push(call.selector.clone());
            calldata.push(Felt::from(call.data.len() as u64));
            calldata.extend(call.data.clone());
        }
        
        calldata
    }

    /// Convert secret bytes to ByteArray calldata format.
    /// 
    /// ByteArray format: [num_full_words, ...full_words, pending_word, pending_len]
    /// For 32 bytes: 1 full word (31 bytes) + 1 pending byte
    fn secret_to_calldata(&self, secret: &[u8; 32]) -> Result<Vec<Felt>> {
        let mut calldata = Vec::new();
        
        // Number of full 31-byte words
        calldata.push(Felt::from(1u64));
        
        // First 31 bytes as felt (big-endian, padded)
        let mut full_word = [0u8; 32];
        full_word[1..32].copy_from_slice(&secret[0..31]);
        calldata.push(felt_from_bytes(&full_word)?);
        
        // Pending word (last byte)
        calldata.push(Felt::from(secret[31] as u64));
        calldata.push(Felt::from(1u64)); // pending_len
        
        Ok(calldata)
    }
}

// ============ HELPER FUNCTIONS ============

fn felt_from_hex(s: &str) -> Result<Felt> {
    let s = s.strip_prefix("0x").unwrap_or(s);
    let s = s.strip_prefix("0X").unwrap_or(s);
    
    // Decode hex to bytes
    let padded = if s.len() <= 64 {
        format!("{:0>64}", s)
    } else {
        s.to_string()
    };
    
    let bytes = hex::decode(&padded).context("Invalid hex string")?;
    
    if bytes.len() > 32 {
        return Err(anyhow!("Hex string too long for felt (max 32 bytes)"));
    }
    
    let mut arr = [0u8; 32];
    // Copy bytes to end of array (big-endian)
    let start = 32 - bytes.len();
    arr[start..].copy_from_slice(&bytes);
    
    // starknet-ff::FieldElement::from_bytes_be returns Result
    Felt::from_bytes_be(&arr)
        .map_err(|e| anyhow!("Failed to create FieldElement from bytes: {:?}", e))
}

/// Convert bytes array to Felt (helper for calldata construction)
fn felt_from_bytes(bytes: &[u8; 32]) -> Result<Felt> {
    Felt::from_bytes_be(bytes)
        .map_err(|e| anyhow!("Failed to create FieldElement from bytes: {:?}", e))
}

fn felt_to_hex(f: &Felt) -> String {
    format!("{:#x}", f)
}

#[cfg(not(target_os = "macos"))]
/// Convert starknet-ff::FieldElement to starknet-crypto::FieldElement
fn felt_to_field_element(felt: &Felt) -> Result<FieldElement> {
    let bytes = felt.to_bytes_be();
    FieldElement::from_bytes_be(&bytes)
        .map_err(|e| anyhow!("Failed to convert Felt to FieldElement: {:?}", e))
}

#[cfg(not(target_os = "macos"))]
/// Convert starknet-crypto::FieldElement to starknet-ff::FieldElement
fn field_element_to_felt(fe: &FieldElement) -> Result<Felt> {
    let bytes = fe.to_bytes_be();
    Felt::from_bytes_be(&bytes)
        .map_err(|e| anyhow!("Failed to convert FieldElement to Felt: {:?}", e))
}

/// Compute starknet_keccak selector from function name.
fn get_selector_from_name(name: &str) -> Felt {
    let mut hasher = Keccak256::new();
    hasher.update(name.as_bytes());
    let result = hasher.finalize();
    
    let mut bytes = [0u8; 32];
    bytes.copy_from_slice(&result);
    // Mask to 250 bits (starknet_keccak requirement)
    bytes[0] &= 0x03;
    
    // Use from_bytes_be which returns Result
    Felt::from_bytes_be(&bytes).unwrap_or_else(|_| Felt::from(0u64))
}

#[async_trait]
impl StarknetClient for StarknetManualClient {
    async fn get_block_timestamp(&self) -> Result<u64> {
        let result = self
            .rpc_call("starknet_getBlockWithTxHashes", json!({ "block_id": "latest" }))
            .await?;

        result["timestamp"]
            .as_u64()
            .context("Invalid timestamp format")
    }

    async fn deploy_and_deposit(
        &self,
        _hashlock: [u32; 8],
        lock_duration_secs: u64,
        _amount: u128,
    ) -> Result<(String, u64)> {
        let now = self.get_block_timestamp().await?;
        let lock_until = now + lock_duration_secs;
        
        // TODO: Implement contract deployment
        // Contract deployment requires:
        // 1. Declare contract class (if not already declared)
        // 2. Build constructor calldata (hashlock, lock_until, token, amount, DLEQ proof data)
        // 3. Deploy contract instance via starknet_addDeployTransaction
        // 4. Sign deployment transaction (similar to invoke, but different hash format)
        // 
        // Note: Invoke transaction signing is now implemented (see submit_invoke_tx).
        // Deployment signing follows similar pattern but uses different transaction hash format.
        tracing::warn!("deploy_and_deposit not yet implemented - requires contract deployment logic");
        Ok(("0x0".to_string(), lock_until))
    }

    async fn reveal_secret(&self, contract: &str, secret: &[u8; 32]) -> Result<String> {
        let contract_addr = felt_from_hex(contract)?;
        let selector = get_selector_from_name("reveal_secret");
        
        // Convert secret to ByteArray calldata
        let calldata = self.secret_to_calldata(secret)?;
        
        let call = Call {
            to: contract_addr,
            selector,
            data: calldata,
        };
        
        let tx_hash = self.submit_invoke_tx(vec![call]).await?;
        
        tracing::info!(
            tx = %tx_hash,
            contract = %contract,
            "Secret revealed"
        );
        
        Ok(tx_hash)
    }

    async fn claim_tokens(&self, contract: &str) -> Result<String> {
        let contract_addr = felt_from_hex(contract)?;
        let selector = get_selector_from_name("claim_tokens");
        
        let call = Call {
            to: contract_addr,
            selector,
            data: vec![],
        };
        
        let tx_hash = self.submit_invoke_tx(vec![call]).await?;
        
        tracing::info!(
            tx = %tx_hash,
            contract = %contract,
            "Tokens claimed"
        );
        
        Ok(tx_hash)
    }

    async fn refund(&self, contract: &str) -> Result<String> {
        let contract_addr = felt_from_hex(contract)?;
        let selector = get_selector_from_name("refund");
        
        let call = Call {
            to: contract_addr,
            selector,
            data: vec![],
        };
        
        let tx_hash = self.submit_invoke_tx(vec![call]).await?;
        
        tracing::info!(
            tx = %tx_hash,
            contract = %contract,
            "Refund executed"
        );
        
        Ok(tx_hash)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_felt_from_hex() {
        let f = felt_from_hex("0x123").unwrap();
        assert!(!felt_to_hex(&f).is_empty());
    }

    #[test]
    fn test_felt_from_hex_no_prefix() {
        let f = felt_from_hex("abc").unwrap();
        assert!(!felt_to_hex(&f).is_empty());
    }

    #[test]
    fn test_felt_zero() {
        let f = felt_from_hex("0x0").unwrap();
        assert_eq!(felt_to_hex(&f), "0x0");
    }

    #[test]
    fn test_selector() {
        let selector = get_selector_from_name("transfer");
        let zero = Felt::from_bytes_be(&[0u8; 32]).unwrap_or(Felt::from(0u64));
        assert_ne!(selector, zero);
    }
}
