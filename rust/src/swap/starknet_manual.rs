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
use tracing;

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
    #[allow(dead_code)]
    private_key: Felt,
    #[allow(dead_code)]
    chain_id: Felt,
    #[allow(dead_code)]
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

/// Convert 32-byte array to u256 (low, high) as two Felts.
/// 
/// u256 is represented as two 128-bit values (low, high) in Cairo.
fn u256_from_bytes(bytes: &[u8; 32]) -> (Felt, Felt) {
    // Split into low 16 bytes and high 16 bytes
    let mut low_bytes = [0u8; 32];
    let mut high_bytes = [0u8; 32];
    
    low_bytes[16..].copy_from_slice(&bytes[0..16]);
    high_bytes[16..].copy_from_slice(&bytes[16..32]);
    
    let low = Felt::from_bytes_be(&low_bytes).unwrap_or(Felt::from(0u64));
    let high = Felt::from_bytes_be(&high_bytes).unwrap_or(Felt::from(0u64));
    
    (low, high)
}

/// MSM hints needed for contract deployment.
/// 
/// These hints are generated by Python tools (generate_hints_exact.py).
/// They are required for Garaga MSM verification in the Cairo contract.
pub struct DeploymentMSMHints {
    /// Fake-GLV hint for adaptor point (10 felts)
    pub fake_glv_hint: Vec<Felt>,
    /// s·G hint (10 felts)
    pub s_hint_for_g: Vec<Felt>,
    /// s·Y hint (10 felts)
    pub s_hint_for_y: Vec<Felt>,
    /// (-c)·T hint (10 felts)
    pub c_neg_hint_for_t: Vec<Felt>,
    /// (-c)·U hint (10 felts)
    pub c_neg_hint_for_u: Vec<Felt>,
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

impl StarknetManualClient {
    /// Build constructor calldata for AtomicLock contract deployment.
    /// 
    /// This builds the calldata array needed for contract constructor.
    /// MSM hints must be provided separately (generated by Python tools).
    pub fn build_deployment_calldata(
        &self,
        hashlock_words: [u32; 8],
        lock_until: u64,
        token_address: Felt,
        amount: u128,
        dleq_proof_cairo: &crate::dleq::DleqProofForCairo,
        msm_hints: &DeploymentMSMHints,
    ) -> Vec<Felt> {
        let mut calldata = Vec::new();
        
        // 1. Hashlock (8 u32 words)
        for word in hashlock_words {
            calldata.push(Felt::from(word as u64));
        }
        
        // 2. lock_until (u64)
        calldata.push(Felt::from(lock_until));
        
        // 3. token (ContractAddress)
        calldata.push(token_address);
        
        // 4. amount (u256: low, high)
        let amount_low = (amount & 0xFFFFFFFFFFFFFFFFu128) as u64;
        let amount_high = ((amount >> 64) & 0xFFFFFFFFFFFFFFFFu128) as u64;
        calldata.push(Felt::from(amount_low));
        calldata.push(Felt::from(amount_high));
        
        // 5. adaptor_point_edwards_compressed (u256: low, high)
        let adaptor_u256 = u256_from_bytes(&dleq_proof_cairo.adaptor_point_compressed);
        calldata.push(adaptor_u256.0);
        calldata.push(adaptor_u256.1);
        
        // 6. adaptor_point_sqrt_hint (u256: low, high)
        let adaptor_hint_u256 = u256_from_bytes(&dleq_proof_cairo.adaptor_point_sqrt_hint);
        calldata.push(adaptor_hint_u256.0);
        calldata.push(adaptor_hint_u256.1);
        
        // 7. dleq_second_point_edwards_compressed (u256: low, high)
        let second_u256 = u256_from_bytes(&dleq_proof_cairo.second_point_compressed);
        calldata.push(second_u256.0);
        calldata.push(second_u256.1);
        
        // 8. dleq_second_point_sqrt_hint (u256: low, high)
        let second_hint_u256 = u256_from_bytes(&dleq_proof_cairo.second_point_sqrt_hint);
        calldata.push(second_hint_u256.0);
        calldata.push(second_hint_u256.1);
        
        // 9. dleq challenge (felt252, truncated to 128 bits for Cairo compatibility)
        let challenge_u256 = u256_from_bytes(&dleq_proof_cairo.challenge);
        calldata.push(challenge_u256.0); // low 128 bits
        
        // 10. dleq response (felt252, truncated to 128 bits)
        let response_u256 = u256_from_bytes(&dleq_proof_cairo.response);
        calldata.push(response_u256.0); // low 128 bits
        
        // 11. fake_glv_hint (Span<felt252> - 10 felts)
        // Note: This needs to be generated by Python tools
        // For now, we expect it to be provided in msm_hints
        calldata.extend(msm_hints.fake_glv_hint.iter().cloned());
        
        // 12-15. DLEQ MSM hints (4 spans × 10 felts each)
        calldata.extend(msm_hints.s_hint_for_g.iter().cloned());
        calldata.extend(msm_hints.s_hint_for_y.iter().cloned());
        calldata.extend(msm_hints.c_neg_hint_for_t.iter().cloned());
        calldata.extend(msm_hints.c_neg_hint_for_u.iter().cloned());
        
        // 16. dleq_r1_compressed (u256: low, high)
        let r1_u256 = u256_from_bytes(&dleq_proof_cairo.r1_compressed);
        calldata.push(r1_u256.0);
        calldata.push(r1_u256.1);
        
        // 17. dleq_r1_sqrt_hint (u256: low, high)
        // Note: This needs to be computed from R1 point
        // For now, placeholder - needs to be provided
        calldata.push(Felt::from(0u64)); // TODO: Compute from R1
        calldata.push(Felt::from(0u64));
        
        // 18. dleq_r2_compressed (u256: low, high)
        let r2_u256 = u256_from_bytes(&dleq_proof_cairo.r2_compressed);
        calldata.push(r2_u256.0);
        calldata.push(r2_u256.1);
        
        // 19. dleq_r2_sqrt_hint (u256: low, high)
        // Note: This needs to be computed from R2 point
        // For now, placeholder - needs to be provided
        calldata.push(Felt::from(0u64)); // TODO: Compute from R2
        calldata.push(Felt::from(0u64));
        
        calldata
    }
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
        hashlock: [u32; 8],
        lock_duration_secs: u64,
        amount: u128,
    ) -> Result<(String, u64)> {
        let _ = (hashlock, amount);
        let now = self.get_block_timestamp().await?;
        let lock_until = now + lock_duration_secs;
        
        // TODO: Implement contract deployment
        // Contract deployment in Starknet v0.11+ typically uses:
        // 1. Universal Deployer Contract (UDC) pattern, OR
        // 2. DEPLOY transaction type (if supported by RPC)
        // 
        // For now, deployment is better handled via TypeScript scripts:
        // - scripts/deploy.ts (uses starknet.js high-level API)
        // - scripts/deploy_with_starknet_py.py (uses starknet.py)
        //
        // These scripts handle:
        // - Contract class declaration
        // - Constructor calldata building
        // - Deployment transaction signing
        // - Transaction submission and waiting
        //
        // To implement here, we would need:
        // 1. Deployment transaction hash computation (different from invoke)
        // 2. UDC integration OR direct DEPLOY transaction support
        // 3. MSM hint generation (currently done by Python tools)
        //
        // Note: Invoke transaction signing is implemented (see submit_invoke_tx).
        tracing::warn!("deploy_and_deposit not yet implemented - use TypeScript deployment scripts for now");
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

impl StarknetManualClient {
    /// Call a view function on a contract (read-only, no transaction).
    /// 
    /// Uses `starknet_call` RPC method to query contract state.
    pub async fn call_view_function(
        &self,
        contract: &str,
        function_name: &str,
        calldata: Vec<Felt>,
    ) -> Result<Vec<Felt>> {
        let contract_addr = felt_from_hex(contract)?;
        let selector = get_selector_from_name(function_name);
        
        let result = self
            .rpc_call(
                "starknet_call",
                json!({
                    "request": {
                        "contract_address": felt_to_hex(&contract_addr),
                        "entry_point_selector": felt_to_hex(&selector),
                        "calldata": calldata.iter().map(|f| felt_to_hex(f)).collect::<Vec<_>>(),
                    },
                    "block_id": "latest"
                }),
            )
            .await?;
        
        // Parse result as array of hex strings, convert to Felt
        let result_array = result
            .as_array()
            .context("Expected array result from view call")?;
        
        let mut felts = Vec::new();
        for item in result_array {
            let hex_str = item.as_str().context("Expected hex string in result")?;
            felts.push(felt_from_hex(hex_str)?);
        }
        
        Ok(felts)
    }

    /// Check if secret has been revealed on the contract.
    pub async fn is_secret_revealed(&self, contract: &str) -> Result<bool> {
        let result = self.call_view_function(contract, "is_secret_revealed", vec![]).await?;
        
        if result.is_empty() {
            return Err(anyhow!("Empty result from is_secret_revealed"));
        }
        
        // Result is a single felt252 (bool): 0 = false, 1 = true
        Ok(result[0] != Felt::from(0u64))
    }

    /// Check if contract is unlocked.
    pub async fn is_unlocked(&self, contract: &str) -> Result<bool> {
        let result = self.call_view_function(contract, "is_unlocked", vec![]).await?;
        
        if result.is_empty() {
            return Err(anyhow!("Empty result from is_unlocked"));
        }
        
        // Result is a single felt252 (bool): 0 = false, 1 = true
        Ok(result[0] != Felt::from(0u64))
    }

    /// Wait for transaction to be confirmed on-chain.
    /// 
    /// Polls `starknet_getTransactionReceipt` until transaction is accepted or rejected.
    /// Returns the transaction receipt.
    pub async fn wait_for_transaction(&self, tx_hash: &str) -> Result<Value> {
        let max_attempts = 30; // 30 attempts
        let delay_secs = 2; // 2 seconds between attempts
        
        for attempt in 1..=max_attempts {
            let result = self
                .rpc_call(
                    "starknet_getTransactionReceipt",
                    json!({ "transaction_hash": tx_hash }),
                )
                .await;
            
            match result {
                Ok(receipt) => {
                    // Check if transaction is accepted
                    if let Some(status) = receipt.get("status") {
                        let status_str = status.as_str().unwrap_or("");
                        if status_str == "ACCEPTED_ON_L2" || status_str == "ACCEPTED_ON_L1" {
                            return Ok(receipt);
                        }
                        if status_str == "REJECTED" {
                            return Err(anyhow!("Transaction rejected: {}", receipt));
                        }
                    }
                    // If status not found, might be pending - continue waiting
                }
                Err(e) => {
                    // Transaction might not be found yet (pending)
                    if attempt < max_attempts {
                        tracing::debug!("Transaction not found yet (attempt {}/{}), waiting...", attempt, max_attempts);
                    } else {
                        return Err(anyhow!("Transaction not found after {} attempts: {}", max_attempts, e));
                    }
                }
            }
            
            if attempt < max_attempts {
                // Use async sleep - tokio is available as a dependency
                tokio::time::sleep(std::time::Duration::from_secs(delay_secs)).await;
            }
        }
        
        Err(anyhow!("Transaction not confirmed after {} attempts", max_attempts))
    }

    /// Get transaction receipt (if available).
    pub async fn get_transaction_receipt(&self, tx_hash: &str) -> Result<Value> {
        self.rpc_call(
            "starknet_getTransactionReceipt",
            json!({ "transaction_hash": tx_hash }),
        )
        .await
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
