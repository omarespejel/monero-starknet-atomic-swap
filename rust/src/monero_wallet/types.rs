//! Monero Wallet RPC Types

/// Transfer result from wallet RPC
#[derive(Debug, Clone)]
pub struct TransferResult {
    pub tx_hash: String,
    pub tx_key: String,
    pub amount: u64, // Amount in piconero (atomic units)
    pub fee: u64,    // Fee in piconero
}

/// Transfer information from blockchain
#[derive(Debug, Clone)]
pub struct TransferInfo {
    pub amount: u64, // Amount in piconero
    pub confirmations: u64,
    pub height: u64,
    pub unlock_time: u64,
}

