//! Monero integration for atomic swaps.
//!
//! Uses KEY SPLITTING approach (not CLSAG modification):
//! - key_splitting: Split/recover spend keys
//! - transaction: Create Monero transactions using Serai's audited code
//! - finality: Wait for transaction finality (confirmations)

pub mod key_splitting;
pub mod transaction;
pub mod finality;

// Re-export main types
pub use key_splitting::SwapKeyPair;
pub use finality::{
    wait_for_finality,
    wait_for_default_finality,
    MoneroWalletClient,
    DEFAULT_CONFIRMATIONS,
    DEFAULT_POLL_INTERVAL_SECS,
};
