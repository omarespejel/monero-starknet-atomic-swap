use serde::{Deserialize, Serialize};

/// Event emitted when secret is revealed (Phase 1)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SecretRevealedEvent {
    pub contract_address: String,
    pub revealer: String,
    pub secret_hash: u32,
    pub claimable_after: u64,
    pub block_number: u64,
    pub transaction_hash: String,
}

/// Event emitted when tokens are claimed (Phase 2)
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TokensClaimedEvent {
    pub contract_address: String,
    pub claimer: String,
    pub amount: u128,
    pub reveal_timestamp: u64,
    pub claim_timestamp: u64,
}

/// Swap state tracked by watchtower
#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[allow(dead_code)]
pub enum SwapState {
    /// Contract deployed, waiting for secret revelation
    Locked,
    /// Secret revealed, grace period active
    Revealed {
        revealer: String,
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
    #[allow(dead_code)]
    Critical,
}

/// Alert to send to operators
#[derive(Debug, Clone)]
pub struct Alert {
    pub level: AlertLevel,
    pub title: String,
    pub message: String,
    pub contract_address: String,
    #[allow(dead_code)]
    pub timestamp: u64,
}

