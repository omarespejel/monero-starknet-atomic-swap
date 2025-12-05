//! Monero adaptor signature module for atomic swaps.
//!
//! This module implements key splitting and adaptor signature generation
//! for XMR↔Starknet atomic swaps. The adaptor scalar `t` is the same
//! scalar used in Cairo's MSM verification (t·G == adaptor_point).

pub mod key_splitting;
pub mod adaptor_sig;

pub use key_splitting::{split_monero_key, KeyPair};
pub use adaptor_sig::{create_adaptor_signature, finalize_signature, verify_signature, AdaptorSignature};

