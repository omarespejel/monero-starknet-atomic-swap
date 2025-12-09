//! Monero Wallet RPC Integration
//! 
//! Production-grade wallet RPC client based on COMIT Network's
//! battle-tested implementation for atomic swaps.

pub mod client;
pub mod error;
pub mod types;

pub use client::MoneroWallet;
pub use error::MoneroWalletError;
pub use types::*;


