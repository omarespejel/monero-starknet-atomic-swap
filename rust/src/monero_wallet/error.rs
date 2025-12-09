//! Monero Wallet RPC Error Types

use thiserror::Error;

#[derive(Debug, Error)]
pub enum MoneroWalletError {
    #[error("RPC connection failed: {0}")]
    ConnectionFailed(String),
    
    #[error("RPC call failed: {0}")]
    RpcCallFailed(String),
    
    #[error("Invalid response format: {0}")]
    InvalidResponse(String),
    
    #[error("Wallet operation failed: {0}")]
    WalletOperationFailed(String),
    
    #[error("Insufficient balance: required {required}, available {available}")]
    InsufficientBalance {
        required: u64,
        available: u64,
    },
}


