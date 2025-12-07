//! Monero transaction creation using Serai's audited code.
//!
//! This module wraps monero-serai to create standard Monero transactions.
//! The CLSAG signing is handled entirely by the audited library.

use curve25519_dalek::scalar::Scalar;
use anyhow::Result;

// TODO: Uncomment when monero-serai is added as dependency
// use monero_serai::wallet::{SignableTransaction, SpendableOutput};

/// Create a Monero transaction after recovering the full spend key.
/// 
/// This uses Serai's AUDITED transaction builder - no custom CLSAG!
pub fn create_transaction(
    full_spend_key: Scalar,
    // output: SpendableOutput,
    // decoys: Decoys,
    destination: &str,
    amount: u64,
) -> Result<Vec<u8>> {
    // TODO: Implement using monero-serai's SignableTransaction
    // 
    // let signable = SignableTransaction::new(
    //     inputs,
    //     payments,
    //     change_address,
    //     fee_rate,
    // )?;
    // 
    // let signed = signable.sign(&mut rng, &full_spend_key)?;
    // Ok(signed.serialize())
    
    anyhow::bail!("TODO: Implement with monero-serai SignableTransaction")
}

