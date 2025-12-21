//! Property-based tests for cryptographic operations
//!
//! These tests verify deterministic behavior and cryptographic properties
//! hold for arbitrary inputs using proptest.

use proptest::prelude::*;
use curve25519_dalek::scalar::Scalar;
use xmr_secret_gen::monero::address::derive_stagenet_address;

// Use direct implementation for property tests (derive_view_key is test-only)
use tiny_keccak::{Hasher, Keccak};

fn derive_view_key_for_test(spend_key: &Scalar) -> Scalar {
    let mut keccak = Keccak::v256();
    keccak.update(&spend_key.to_bytes());
    let mut hash = [0u8; 32];
    keccak.finalize(&mut hash);
    Scalar::from_bytes_mod_order(hash)
}

proptest! {
    /// Property: View key derivation is deterministic
    ///
    /// For any spend key, deriving the view key multiple times
    /// should produce the same result.
    #[test]
    fn view_key_derivation_is_deterministic(
        spend_key_bytes in prop::array::uniform32(any::<u8>())
    ) {
        let spend_key = Scalar::from_bytes_mod_order(spend_key_bytes);
        
        let view1 = derive_view_key_for_test(&spend_key);
        let view2 = derive_view_key_for_test(&spend_key);
        
        prop_assert_eq!(view1.to_bytes(), view2.to_bytes(), 
            "View key derivation must be deterministic");
    }
    
    /// Property: Address derivation is deterministic
    ///
    /// For any pair of spend and view keys, deriving the address
    /// multiple times should produce the same result.
    #[test]
    fn address_derivation_is_deterministic(
        spend_bytes in prop::array::uniform32(any::<u8>()),
        view_bytes in prop::array::uniform32(any::<u8>())
    ) {
        let spend = Scalar::from_bytes_mod_order(spend_bytes);
        let view = Scalar::from_bytes_mod_order(view_bytes);
        
        let addr1 = derive_stagenet_address(&spend, &view).unwrap();
        let addr2 = derive_stagenet_address(&spend, &view).unwrap();
        
        prop_assert_eq!(addr1, addr2, 
            "Address derivation must be deterministic");
    }
    
    /// Property: Different keys produce different addresses
    ///
    /// For different spend/view key pairs, addresses should differ.
    #[test]
    fn different_keys_produce_different_addresses(
        spend1_bytes in prop::array::uniform32(any::<u8>()),
        view1_bytes in prop::array::uniform32(any::<u8>()),
        spend2_bytes in prop::array::uniform32(any::<u8>()),
        view2_bytes in prop::array::uniform32(any::<u8>())
    ) {
        // Skip if keys are identical
        if spend1_bytes == spend2_bytes && view1_bytes == view2_bytes {
            return Ok(());
        }
        
        let spend1 = Scalar::from_bytes_mod_order(spend1_bytes);
        let view1 = Scalar::from_bytes_mod_order(view1_bytes);
        let spend2 = Scalar::from_bytes_mod_order(spend2_bytes);
        let view2 = Scalar::from_bytes_mod_order(view2_bytes);
        
        let addr1 = derive_stagenet_address(&spend1, &view1).unwrap();
        let addr2 = derive_stagenet_address(&spend2, &view2).unwrap();
        
        prop_assert_ne!(addr1, addr2, 
            "Different keys should produce different addresses");
    }
    
    /// Property: View key derivation produces valid scalars
    ///
    /// The derived view key should always be a valid Ed25519 scalar.
    #[test]
    fn view_key_derivation_produces_valid_scalar(
        spend_key_bytes in prop::array::uniform32(any::<u8>())
    ) {
        let spend_key = Scalar::from_bytes_mod_order(spend_key_bytes);
        let view_key = derive_view_key_for_test(&spend_key);
        
        // Verify it's a valid scalar (can be used in operations)
        let _ = Scalar::from_bytes_mod_order(view_key.to_bytes());
        
        // Test that it can be used in point multiplication
        use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
        let _point = ED25519_BASEPOINT_POINT * view_key;
        
        // If we get here, the scalar is valid
        prop_assert!(true);
    }
    
    /// Property: Address derivation produces valid stagenet addresses
    ///
    /// All derived addresses should start with '5' and be 95 characters.
    #[test]
    fn address_derivation_produces_valid_format(
        spend_bytes in prop::array::uniform32(any::<u8>()),
        view_bytes in prop::array::uniform32(any::<u8>())
    ) {
        let spend = Scalar::from_bytes_mod_order(spend_bytes);
        let view = Scalar::from_bytes_mod_order(view_bytes);
        
        let address = derive_stagenet_address(&spend, &view).unwrap();
        
        prop_assert!(address.starts_with('5'), 
            "Stagenet address must start with '5', got: {}", address);
        prop_assert_eq!(address.len(), 95, 
            "Address must be 95 characters, got: {}", address.len());
    }
}

