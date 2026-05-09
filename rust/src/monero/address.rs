//! Monero address derivation using monero-rs (battle-tested)
//!
//! AUDITOR APPROVED: Uses monero-rs for all address encoding
//! - Correct Monero base58 (8-byte blocks)
//! - Correct checksum (Keccak-256)
//! - Correct network bytes
//!
//! DO NOT use custom base58 implementation - monero-rs is the ONLY production-safe option.

use anyhow::{Context, Result};
use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::scalar::Scalar;
use monero::util::address::Address;
use monero::util::key::PublicKey;
use monero::Network;

/// Derive Monero stagenet address from spend and view keys.
///
/// SAFETY: Uses monero-rs v0.21 (battle-tested since 2018)
///
/// # Arguments
/// * `spend_key` - Private spend key (scalar)
/// * `view_key` - Private view key (scalar)
///
/// # Returns
/// Base58-encoded Monero stagenet address string (starts with '5')
pub fn derive_stagenet_address(spend_key: &Scalar, view_key: &Scalar) -> Result<String> {
    derive_address(spend_key, view_key, Network::Stagenet)
}

/// Derive Monero mainnet address from spend and view keys.
///
/// SAFETY: Uses monero-rs v0.21 (battle-tested since 2018)
///
/// # Arguments
/// * `spend_key` - Private spend key (scalar)
/// * `view_key` - Private view key (scalar)
///
/// # Returns
/// Base58-encoded Monero mainnet address string (starts with '4')
pub fn derive_mainnet_address(spend_key: &Scalar, view_key: &Scalar) -> Result<String> {
    derive_address(spend_key, view_key, Network::Mainnet)
}

/// Derive a Monero address for an explicit network.
///
/// Use this in production paths instead of hardcoding stagenet/mainnet. A wrong
/// network byte creates a valid-looking address on the wrong network.
pub fn derive_address_for_network(
    spend_key: &Scalar,
    view_key: &Scalar,
    network: Network,
) -> Result<String> {
    derive_address(spend_key, view_key, network)
}

fn derive_address(spend_key: &Scalar, view_key: &Scalar, network: Network) -> Result<String> {
    // 1. Compute public keys: P = k * G
    let public_spend_point = ED25519_BASEPOINT_POINT * spend_key;
    let public_view_point = ED25519_BASEPOINT_POINT * view_key;

    // 2. Convert to monero-rs PublicKey format
    let public_spend = PublicKey::from_slice(&public_spend_point.compress().to_bytes())
        .context("Invalid public spend key")?;
    let public_view = PublicKey::from_slice(&public_view_point.compress().to_bytes())
        .context("Invalid public view key")?;

    // 3. Create address using monero-rs (handles base58 + checksum correctly)
    let address = Address::standard(network, public_spend, public_view);

    Ok(address.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::str::FromStr;

    #[test]
    fn test_stagenet_address_format() {
        let spend_key = Scalar::from(42u64);
        let view_key = Scalar::from(99u64);

        let address = derive_stagenet_address(&spend_key, &view_key).unwrap();

        // Stagenet addresses start with '5'
        assert!(
            address.starts_with('5'),
            "Stagenet address must start with '5', got: {}",
            address
        );
        assert_eq!(
            address.len(),
            95,
            "Address should be 95 chars, got: {}",
            address.len()
        );
    }

    #[test]
    fn test_mainnet_address_format() {
        let spend_key = Scalar::from(42u64);
        let view_key = Scalar::from(99u64);

        let address = derive_mainnet_address(&spend_key, &view_key).unwrap();

        // Mainnet addresses start with '4'
        assert!(
            address.starts_with('4'),
            "Mainnet address must start with '4', got: {}",
            address
        );
        assert_eq!(
            address.len(),
            95,
            "Address should be 95 chars, got: {}",
            address.len()
        );
    }

    #[test]
    fn test_address_roundtrip() {
        let spend_key = Scalar::from(42u64);
        let view_key = Scalar::from(99u64);

        let address_str = derive_stagenet_address(&spend_key, &view_key).unwrap();

        // Verify it parses back (validates checksum)
        let parsed = Address::from_str(&address_str);
        assert!(
            parsed.is_ok(),
            "Address should parse back (validates checksum): {}",
            address_str
        );
    }

    #[test]
    fn test_address_deterministic() {
        let spend_key = Scalar::from(123u64);
        let view_key = Scalar::from(456u64);

        let addr1 = derive_stagenet_address(&spend_key, &view_key).unwrap();
        let addr2 = derive_stagenet_address(&spend_key, &view_key).unwrap();

        // Same keys should produce same address
        assert_eq!(addr1, addr2, "Address derivation should be deterministic");
    }

    #[test]
    fn test_different_keys_different_addresses() {
        let spend1 = Scalar::from(1u64);
        let view1 = Scalar::from(2u64);
        let spend2 = Scalar::from(3u64);
        let view2 = Scalar::from(4u64);

        let addr1 = derive_stagenet_address(&spend1, &view1).unwrap();
        let addr2 = derive_stagenet_address(&spend2, &view2).unwrap();

        // Different keys should produce different addresses
        assert_ne!(
            addr1, addr2,
            "Different keys should produce different addresses"
        );
    }
}
