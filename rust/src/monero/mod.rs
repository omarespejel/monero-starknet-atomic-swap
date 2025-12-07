//! Monero integration for atomic swaps.
//!
//! Uses KEY SPLITTING approach (not CLSAG modification):
//! - key_splitting: Split/recover spend keys
//! - transaction: Create Monero transactions using Serai's audited code

pub mod key_splitting;
pub mod transaction;

// Re-export main types
pub use key_splitting::SwapKeyPair;
