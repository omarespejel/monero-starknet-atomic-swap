//! Swap state machine driver.

use anyhow::{anyhow, Context, Result};
use async_trait::async_trait;

use super::state::SwapState;
use super::db::SwapDb;
use crate::monero::{wait_for_finality, MoneroWalletClient, DEFAULT_CONFIRMATIONS, DEFAULT_POLL_INTERVAL_SECS, claim_monero_after_reveal};
use crate::monero_wallet::MoneroWallet;
use curve25519_dalek::scalar::Scalar;
use zeroize::{Zeroize, Zeroizing};

/// Trait for Starknet operations (enables mocking).
#[async_trait]
pub trait StarknetClient: Send + Sync {
    /// Deploy AtomicLock contract and deposit tokens.
    async fn deploy_and_deposit(
        &self,
        hashlock: [u32; 8],
        lock_duration_secs: u64,
        amount: u128,
    ) -> Result<(String, u64)>; // (contract_address, lock_until)

    /// Call reveal_secret on the contract.
    async fn reveal_secret(&self, contract: &str, secret: &[u8; 32]) -> Result<String>;

    /// Call claim_tokens after grace period.
    async fn claim_tokens(&self, contract: &str) -> Result<String>;

    /// Call refund after timeout.
    async fn refund(&self, contract: &str) -> Result<String>;

    /// Get current block timestamp.
    async fn get_block_timestamp(&self) -> Result<u64>;
}

/// Grace period in seconds (2 hours).
pub const GRACE_PERIOD_SECS: u64 = 7200;

/// Run one step of the state machine. Returns new state or None if terminal/waiting.
pub async fn step<D, M, S>(
    state: &SwapState,
    db: &D,
    monero: &M,
    starknet: &S,
    secret: &[u8; 32],
) -> Result<Option<SwapState>>
where
    D: SwapDb,
    M: MoneroWalletClient,
    S: StarknetClient,
{
    // Check timeout first (for states that have lock_until)
    if let Some(lock_until) = get_lock_until(state) {
        let now = starknet.get_block_timestamp().await?;
        if now >= lock_until && can_refund(state) {
            let new_state = handle_refund(state, starknet).await?;
            db.save(&new_state)?;
            return Ok(Some(new_state));
        }
    }

    let new_state = match state {
        SwapState::Created { swap_id, lock_duration_secs, amount, expected_monero_amount, hashlock, monero_restore_height } => {
            tracing::info!("[{}] Deploying Starknet contract...", swap_id);
            
            let (contract_address, lock_until) = starknet
                .deploy_and_deposit(*hashlock, *lock_duration_secs, *amount)
                .await
                .context("Failed to deploy contract")?;

            SwapState::StarknetLocked {
                swap_id: swap_id.clone(),
                contract_address,
                lock_until,
                expected_monero_amount: *expected_monero_amount,
                hashlock: *hashlock,
                monero_restore_height: *monero_restore_height,
            }
        }

        SwapState::StarknetLocked { .. } => {
            // Waiting for external XMR transaction - no automatic transition
            // Use `resume_with_xmr_txid` to advance
            return Ok(None);
        }

        SwapState::XmrSent { swap_id, contract_address, lock_until, monero_txid, .. } => {
            tracing::info!("[{}] Waiting for {} confirmations...", swap_id, DEFAULT_CONFIRMATIONS);
            
            let info = wait_for_finality(
                monero,
                monero_txid,
                DEFAULT_CONFIRMATIONS,
                DEFAULT_POLL_INTERVAL_SECS,
                0, // no timeout (swap timeout handled separately)
            ).await.context("XMR finality wait failed")?;

            tracing::info!("[{}] XMR confirmed ({} confirmations)", swap_id, info.confirmations);

            SwapState::XmrConfirmed {
                swap_id: swap_id.clone(),
                contract_address: contract_address.clone(),
                lock_until: *lock_until,
                monero_txid: monero_txid.clone(),
            }
        }

        SwapState::XmrConfirmed { swap_id, contract_address, .. } => {
            tracing::info!("[{}] Revealing secret on Starknet...", swap_id);
            
            let _tx = starknet
                .reveal_secret(contract_address, secret)
                .await
                .context("Failed to reveal secret")?;

            let reveal_timestamp = starknet.get_block_timestamp().await?;

            // Note: partial_spend_key and claim_destination should be set by caller
            // when creating the swap. For now, we'll use None and require them to be set
            // before claiming Monero.
            SwapState::SecretRevealed {
                swap_id: swap_id.clone(),
                contract_address: contract_address.clone(),
                reveal_timestamp,
                monero_restore_height: None, // Should be preserved from earlier states
                partial_spend_key: None, // Must be set before claiming
                claim_destination: None, // Must be set before claiming
            }
        }

        SwapState::SecretRevealed { swap_id, contract_address, reveal_timestamp, .. } => {
            let now = starknet.get_block_timestamp().await?;
            
            if now < reveal_timestamp + GRACE_PERIOD_SECS {
                // Still in grace period
                let remaining = (reveal_timestamp + GRACE_PERIOD_SECS) - now;
                tracing::info!("[{}] Grace period: {} seconds remaining", swap_id, remaining);
                return Ok(None);
            }

            tracing::info!("[{}] Claiming tokens...", swap_id);
            
            let tx = starknet
                .claim_tokens(contract_address)
                .await
                .context("Failed to claim tokens")?;

            SwapState::Completed {
                swap_id: swap_id.clone(),
                starknet_tx: tx,
                monero_txid: String::new(), // Could track from earlier state
            }
        }

        // Terminal states
        SwapState::Completed { .. } | SwapState::Refunded { .. } => {
            return Ok(None);
        }
    };

    db.save(&new_state)?;
    Ok(Some(new_state))
}

/// Resume a swap by providing the XMR transaction ID.
///
/// # Security
/// Validates that the received Monero amount meets or exceeds the expected amount.
/// This prevents fund loss attacks where an attacker sends less XMR than agreed.
/// The expected amount is read from the state, ensuring consistency.
///
/// # Arguments
/// * `current` - Current swap state (must be `StarknetLocked`)
/// * `monero_txid` - Transaction ID of the Monero transfer
/// * `monero_amount` - Actual amount received (in piconero)
pub fn resume_with_xmr_txid(
    current: &SwapState,
    monero_txid: String,
    monero_amount: u64,
) -> Result<SwapState> {
    match current {
        SwapState::StarknetLocked { swap_id, contract_address, lock_until, expected_monero_amount, hashlock: _, .. } => {
            // SECURITY: Validate amount matches expected (from state)
            if monero_amount < *expected_monero_amount {
                return Err(anyhow!(
                    "XMR amount {} piconero is less than expected {} piconero (difference: {} piconero)",
                    monero_amount,
                    expected_monero_amount,
                    expected_monero_amount - monero_amount
                ));
            }

            Ok(SwapState::XmrSent {
                swap_id: swap_id.clone(),
                contract_address: contract_address.clone(),
                lock_until: *lock_until,
                monero_txid,
                monero_amount,
            })
        }
        _ => Err(anyhow!("Can only resume from StarknetLocked state, got {:?}", current)),
    }
}

// Helper functions

fn get_lock_until(state: &SwapState) -> Option<u64> {
    match state {
        SwapState::StarknetLocked { lock_until, .. }
        | SwapState::XmrSent { lock_until, .. }
        | SwapState::XmrConfirmed { lock_until, .. } => Some(*lock_until),
        _ => None,
    }
}

fn can_refund(state: &SwapState) -> bool {
    matches!(
        state,
        SwapState::StarknetLocked { .. } | SwapState::XmrSent { .. } | SwapState::XmrConfirmed { .. }
    )
}

async fn handle_refund<S: StarknetClient>(state: &SwapState, starknet: &S) -> Result<SwapState> {
    let (swap_id, contract_address) = match state {
        SwapState::StarknetLocked { swap_id, contract_address, .. }
        | SwapState::XmrSent { swap_id, contract_address, .. }
        | SwapState::XmrConfirmed { swap_id, contract_address, .. } => {
            (swap_id.clone(), contract_address.clone())
        }
        _ => return Err(anyhow!("Cannot refund from state: {:?}", state)),
    };

    tracing::warn!("[{}] Timeout exceeded, initiating refund...", swap_id);
    
    let refund_tx = starknet.refund(&contract_address).await?;

    Ok(SwapState::Refunded {
        swap_id,
        reason: "Timeout exceeded".to_string(),
        refund_tx: Some(refund_tx),
    })
}

/// Handle secret revealed and claim Monero funds.
///
/// This function should be called when the secret `t` is revealed on Starknet.
/// It recovers the full Monero spend key and claims the funds.
///
/// # Arguments
/// * `state` - Current swap state (must be `SecretRevealed`)
/// * `revealed_t_bytes` - The revealed secret `t` as bytes (from Starknet)
/// * `wallet_rpc_url` - Monero wallet-rpc URL
/// * `daemon_rpc_url` - Monero daemon RPC URL
/// * `wallet_dir` - Directory for temporary wallet files
///
/// # Returns
/// Transaction hash of the Monero claim transaction
pub async fn handle_secret_revealed(
    state: &SwapState,
    mut revealed_t_bytes: [u8; 32],
    wallet_rpc_url: &str,
    daemon_rpc_url: &str,
    wallet_dir: &str,
) -> Result<String> {
    let (swap_id, partial_spend_key, claim_destination, restore_height) = match state {
        SwapState::SecretRevealed {
            swap_id,
            partial_spend_key: Some(key),
            claim_destination: Some(dest),
            monero_restore_height,
            ..
        } => (
            swap_id.clone(),
            *key,
            dest.clone(),
            monero_restore_height.unwrap_or(0),
        ),
        SwapState::SecretRevealed { swap_id, .. } => {
            return Err(anyhow!(
                "[{}] Cannot claim Monero: missing partial_spend_key or claim_destination",
                swap_id
            ));
        }
        _ => {
            return Err(anyhow!(
                "Can only claim Monero from SecretRevealed state, got {:?}",
                state
            ));
        }
    };

    // 1. Convert revealed bytes to Scalar
    let t = Zeroizing::new(Scalar::from_bytes_mod_order(revealed_t_bytes));
    revealed_t_bytes.zeroize();

    // 2. Get partial key from swap state
    let x_partial = Zeroizing::new(Scalar::from_bytes_mod_order(partial_spend_key));

    // 3. Create wallet client
    let wallet = MoneroWallet::new(
        wallet_rpc_url.to_string(),
        daemon_rpc_url.to_string(),
        format!("swap_{}", swap_id),
        wallet_dir.to_string(),
    )
    .await
    .context("Failed to create Monero wallet client")?;

    // 4. Claim Monero funds
    let tx_hash = claim_monero_after_reveal(
        &wallet,
        x_partial,
        *t,
        &claim_destination,
        restore_height,
    )
    .await
    .context("Failed to claim Monero funds")?;

    tracing::info!("[{}] Monero funds claimed: tx_hash={}", swap_id, tx_hash);

    Ok(tx_hash)
}

/// Get current Monero block height from daemon.
///
/// Returns the current block height minus a safety margin (10 blocks ≈ 20 minutes).
/// This is used as the restore_height for optimized wallet sync.
pub async fn get_current_monero_height(daemon_url: &str) -> Result<u64> {
    let client = reqwest::Client::new();
    let resp: serde_json::Value = client
        .post(daemon_url)
        .json(&serde_json::json!({
            "jsonrpc": "2.0",
            "id": "0",
            "method": "get_block_count"
        }))
        .send()
        .await
        .context("Failed to query Monero daemon")?
        .json()
        .await
        .context("Failed to parse daemon response")?;

    let height = resp["result"]["count"]
        .as_u64()
        .context("Failed to get block count from daemon response")?;

    // Subtract safety margin (10 blocks ≈ 20 minutes)
    Ok(height.saturating_sub(10))
}

