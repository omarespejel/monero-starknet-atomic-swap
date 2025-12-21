//! Monero adaptor signature module for atomic swaps.
//!
//! **⚠️ NOTE**: This module contains demo/POC code. For production:
//! - Use `monero::SwapKeyPair` (key splitting approach) - production ready
//! - Use `monero-oxide` for CLSAG transaction signing - production ready
//!
//! The `adaptor_sig` module is kept for backward compatibility with demo code
//! but should be replaced with `monero-oxide` for production transactions.

pub mod adaptor_sig;

// Re-export from monero module (production key splitting approach)
pub use crate::monero::SwapKeyPair;

// Legacy exports for backward compatibility (deprecated - demo only)
// TODO: Replace with monero-oxide for production
pub use adaptor_sig::{
    create_adaptor_signature, finalize_signature, verify_signature, AdaptorSignature,
};
