use serde::{Deserialize, Serialize};
use starknet_core::types::Felt;

/// Event emitted when secret is revealed (Phase 1)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecretRevealedEvent {
    pub contract_address: Felt,
    pub revealer: Felt,
    pub secret_hash: u32,
    pub claimable_after: u64,
    pub block_number: u64,
    pub transaction_hash: Felt,
}

/// Event emitted when tokens are claimed (Phase 2)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokensClaimedEvent {
    pub contract_address: Felt,
    pub claimer: Felt,
    pub amount: u128,
    pub reveal_timestamp: u64,
    pub claim_timestamp: u64,
}

/// Swap state tracked by watchtower
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub enum SwapState {
    /// Contract deployed, waiting for secret revelation
    Locked,
    /// Secret revealed, grace period active
    Revealed {
        revealer: Felt,
        claimable_after: u64,
    },
    /// Tokens claimed, swap complete
    Completed,
    /// Swap timed out or refunded
    Expired,
}

/// Alert severity levels
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AlertLevel {
    Info,
    Warning,
    Critical,
}

/// Alert to send to operators
#[derive(Debug, Clone)]
pub struct Alert {
    pub level: AlertLevel,
    pub title: String,
    pub message: String,
    pub contract_address: Felt,
    pub timestamp: u64,
}

