//! Monero integration for atomic swaps.
//!
//! Uses KEY SPLITTING approach (not CLSAG modification):
//! - key_splitting: Split/recover spend keys
//! - transaction: Create Monero transactions using wallet-rpc (auditor-approved, uses Monero's own CLSAG)
//! - decoy_selection: Fetch ring members via wallet-rpc
//! - finality: Wait for transaction finality (confirmations)

pub mod address;
pub mod decoy_selection;
pub mod finality;
pub mod key_splitting;
pub mod transaction;
pub mod two_party_keys;

// Re-export main types
pub use address::{derive_mainnet_address, derive_stagenet_address};
pub use decoy_selection::{fetch_decoys, fetch_decoys_batch};
pub use finality::{
    wait_for_default_finality, wait_for_finality, MoneroWalletClient, DEFAULT_CONFIRMATIONS,
    DEFAULT_POLL_INTERVAL_SECS,
};
pub use key_splitting::SwapKeyPair;
pub use transaction::claim_monero_after_reveal;
pub use two_party_keys::{
    recover_spend_key, AliceKeys, AlicePublicData, BobKeys, BobPublicData, SharedOutput,
};
