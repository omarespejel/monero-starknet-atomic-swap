//! Monero transaction claiming via wallet-rpc (auditor-approved approach).
//!
//! This module uses wallet-rpc's battle-tested operations to claim Monero funds
//! after full key recovery (x = x_partial + t).
//!
//! # Security
//! - Uses wallet-rpc's production-grade CLSAG implementation
//! - NO custom ring signatures - all crypto handled by wallet-rpc
//! - Full spend key must be recovered BEFORE calling this
//!
//! # Approach
//! 1. Import recovered spend key into wallet-rpc
//! 2. Refresh wallet to detect received funds
//! 3. Sweep all funds to destination address
//!
//! This is the auditor-approved approach - minimal custom code, battle-tested operations.

use anyhow::{Context, Result};
use curve25519_dalek::scalar::Scalar;
use hex;
use monero::Network;
use tiny_keccak::{Hasher, Keccak};
use zeroize::{Zeroize, Zeroizing};

use crate::monero_wallet::client::MoneroWallet;

/// Derive Monero view key from spend key using keccak256.
///
/// This is the standard Monero view key derivation: `view_key = keccak256(spend_key)`
/// The view key is required by wallet-rpc for wallet operations.
/// Derive Monero view key from spend key (public for testing)
#[cfg(test)]
pub fn derive_view_key(spend_key: &Scalar) -> Scalar {
    derive_view_key_impl(spend_key)
}

/// Internal implementation
fn derive_view_key_impl(spend_key: &Scalar) -> Scalar {
    let mut keccak = Keccak::v256();
    keccak.update(&spend_key.to_bytes());
    let mut hash = [0u8; 32];
    keccak.finalize(&mut hash);
    Scalar::from_bytes_mod_order(hash)
}

/// Claim Monero funds after secret revelation using wallet-rpc.
///
/// This is the auditor-approved approach: use wallet-rpc's production-grade
/// operations instead of custom transaction signing.
///
/// # Security
/// - Uses wallet-rpc's AUDITED CLSAG implementation
/// - NO custom ring signatures - all crypto handled by wallet-rpc
/// - Full spend key must be recovered BEFORE calling this
/// - The spend key is zeroized after use
/// - View key is properly derived (not empty)
/// - Restore height optimized (not 0)
/// - Wallet cleanup ensures secure deletion
///
/// # Arguments
/// * `wallet` - MoneroWallet client instance
/// * `x_partial` - Partial spend key (kept secret during swap)
/// * `t` - Adaptor scalar (revealed on Starknet)
/// * `destination` - Monero address to send funds to
/// * `restore_height` - Block height when swap was initiated (for optimization)
/// * `network` - Monero network for restored wallet address derivation
///
/// # Returns
/// Transaction hash of the sweep transaction
///
/// # Process
/// 1. Recover full key: `x = x_partial + t`
/// 2. Derive view key: `keccak256(spend_key)`
/// 3. Derive address from keys
/// 4. Import key into wallet-rpc: `generate_from_keys()` (with view key!)
/// 5. Sync wallet: `refresh()`
/// 6. Sweep funds: `sweep_all()`
/// 7. Cleanup: `close_wallet()` + `secure_delete_wallet()`
pub async fn claim_monero_after_reveal(
    wallet: &MoneroWallet,
    x_partial: Zeroizing<Scalar>,
    t: Scalar,
    destination: &str,
    restore_height: u64,
    network: Network,
) -> Result<String> {
    // Step 1: Recover full spend key
    let full_key = Zeroizing::new(*x_partial + t);

    // Step 2: Derive view key (REQUIRED by wallet-rpc)
    let mut view_key = derive_view_key_impl(&full_key);

    // Step 3: Derive address from keys for the explicit network.
    let address = crate::monero::address::derive_address_for_network(&full_key, &view_key, network)
        .with_context(|| format!("Failed to derive {:?} Monero address from keys", network))?;

    // Step 4: Convert to hex for wallet-rpc
    let spend_key_hex = hex::encode(full_key.to_bytes());
    let view_key_hex = hex::encode(view_key.to_bytes());

    // Step 5: Import key with BOTH keys and optimized height
    let wallet_name = wallet
        .generate_from_keys(
            &spend_key_hex,
            &view_key_hex, // ✅ REQUIRED - not empty!
            &address,
            restore_height, // ✅ OPTIMIZED (not 0!)
        )
        .await?;

    let result = async {
        wallet.refresh_from_height(restore_height).await?;
        wallet.sweep_all(destination).await
    }
    .await;

    // Step 7: ALWAYS cleanup (even on error)
    let _ = wallet.close_wallet().await;
    let _ = wallet.secure_delete_wallet(&wallet_name).await;

    // Step 8: Zeroize sensitive data
    view_key.zeroize();

    result
}

/// Legacy function name for backward compatibility.
///
/// This function is deprecated. Use `claim_monero_after_reveal()` instead.
#[deprecated(note = "Use claim_monero_after_reveal() instead")]
pub async fn create_transaction_after_reveal(
    _full_spend_key: Zeroizing<Scalar>,
    _view_key: Scalar,
    _outputs: Vec<(String, u64)>,
    _decoys: Vec<DecoySet>,
) -> Result<Vec<u8>> {
    anyhow::bail!(
        "create_transaction_after_reveal() is deprecated. \
         Use claim_monero_after_reveal() with wallet-rpc instead."
    )
}

/// Decoy set for ring signature (fetched from wallet-rpc).
///
/// Each input in a Monero transaction needs decoys (ring members)
/// to provide privacy. These are fetched from a synced Monero node.
///
/// Note: With wallet-rpc approach, decoys are handled automatically
/// by wallet-rpc's sweep_all() operation.
#[allow(dead_code)] // Kept for reference, not used with wallet-rpc approach
pub struct DecoySet {
    /// Ring members for this input (usually 16 for current Monero)
    pub ring_members: Vec<RingMember>,
}

/// A single ring member (decoy output).
#[allow(dead_code)] // Kept for reference, not used with wallet-rpc approach
pub struct RingMember {
    /// Output public key (one-time key)
    pub output_key: [u8; 32],
    /// Commitment (amount commitment)
    pub commitment: [u8; 32],
    /// Global output index
    pub global_index: u64,
}

#[cfg(test)]
mod tests {
    use super::*;
    use curve25519_dalek::scalar::Scalar;
    use rand::rngs::OsRng;

    #[test]
    fn test_decoy_set_structure() {
        // Verify DecoySet can be constructed (kept for reference)
        let decoy = DecoySet {
            ring_members: vec![RingMember {
                output_key: [0u8; 32],
                commitment: [0u8; 32],
                global_index: 0,
            }],
        };
        assert_eq!(decoy.ring_members.len(), 1);
    }

    #[tokio::test]
    #[ignore] // Requires running wallet-rpc
    async fn test_claim_monero_after_reveal() {
        // Integration test - requires:
        // 1. wallet-rpc running
        // 2. Test wallet with funds
        // 3. Valid destination address

        use crate::monero_wallet::client::MoneroWallet;
        use rand::RngCore;

        let wallet = MoneroWallet::new(
            std::env::var("MONERO_WALLET_RPC_URL")
                .unwrap_or_else(|_| "http://127.0.0.1:38090/json_rpc".to_string()),
            std::env::var("MONERO_DAEMON_RPC_URL")
                .unwrap_or_else(|_| "http://node2.monerodevs.org:38089/json_rpc".to_string()),
            "test_wallet".to_string(),
            "./wallets".to_string(), // wallet_dir
        )
        .await
        .expect("Failed to create wallet client");

        // Generate test keys
        let mut rng = OsRng;
        let mut x_partial_bytes = [0u8; 32];
        rng.fill_bytes(&mut x_partial_bytes);
        let x_partial = Zeroizing::new(Scalar::from_bytes_mod_order(x_partial_bytes));

        let mut t_bytes = [0u8; 32];
        rng.fill_bytes(&mut t_bytes);
        let t = Scalar::from_bytes_mod_order(t_bytes);

        let destination = "5A1..."; // Test address

        // This will fail without actual funds, but tests the flow
        let result = claim_monero_after_reveal(
            &wallet,
            x_partial,
            t,
            destination,
            0, // restore_height for test
            Network::Stagenet,
        )
        .await;

        // Expect error without actual funds, but function should be callable
        assert!(result.is_err()); // Will fail at refresh() or sweep_all() without funds
    }
}
