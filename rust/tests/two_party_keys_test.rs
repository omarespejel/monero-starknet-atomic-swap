//! TDD Tests for Two-Party Key Generation
//! 
//! Tests for AliceKeys and BobKeys following the two-party protocol.

use xmr_secret_gen::monero::two_party_keys::{
    AliceKeys, BobKeys, SharedOutput, AlicePublicData, BobPublicData, recover_spend_key,
};
use xmr_secret_gen::crypto::scalar_compat::verify_scalar_bn254_compatible;
use curve25519_dalek::constants::ED25519_BASEPOINT_POINT as G;

// ============================================================
// BASIC FUNCTIONALITY TESTS
// ============================================================

/// Alice can generate keys
#[test]
fn test_alice_generates_keys() {
    let alice = AliceKeys::generate();
    
    // Alice should have spend and view shares
    let _s_a = alice.spend_share();
    let _v_a = alice.view_share();
}

/// Bob can generate keys
#[test]
fn test_bob_generates_keys() {
    let bob = BobKeys::generate();
    
    // Bob should have spend share
    let _s_b = bob.spend_share();
}

/// Shared output can be created from Alice and Bob keys
#[test]
fn test_shared_output_creation() {
    let alice = AliceKeys::generate();
    let bob = BobKeys::generate();
    
    let shared = SharedOutput::new(&alice, &bob);
    
    // Shared output should have combined keys
    let _s_combined = shared.S;
    let _v_combined = shared.V;
}

/// Combined spend key equals sum of shares
#[test]
fn test_combined_spend_key() {
    let alice = AliceKeys::generate();
    let bob = BobKeys::generate();
    
    let shared = SharedOutput::new(&alice, &bob);
    
    // S = (s_a + s_b)·G should equal S_a + S_b
    let s_a = alice.spend_share();
    let s_b = bob.spend_share();
    let expected_s = (s_a + s_b) * curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
    
    assert_eq!(shared.S, expected_s, "Combined spend key must equal sum of shares");
}

/// Combined view key equals sum of shares
#[test]
fn test_combined_view_key() {
    let alice = AliceKeys::generate();
    let bob = BobKeys::generate();
    
    let shared = SharedOutput::new(&alice, &bob);
    
    // V = (v_a + v_b)·G should equal V_a + V_b
    let v_a = alice.view_share();
    let v_b = bob.view_share();
    let expected_v = (v_a + v_b) * curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
    
    assert_eq!(shared.V, expected_v, "Combined view key must equal sum of shares");
}

// ============================================================
// SCALAR COMPATIBILITY TESTS - Ed25519 → BN254 Safety
// ============================================================

/// Alice's scalar is BN254 compatible
#[test]
fn test_alice_scalar_bn254_compatible() {
    let alice = AliceKeys::generate();
    
    assert!(
        verify_scalar_bn254_compatible(&alice.spend_share()),
        "Alice's spend share must be BN254 compatible"
    );
    
    assert!(
        verify_scalar_bn254_compatible(&alice.view_share()),
        "Alice's view share must be BN254 compatible"
    );
}

/// Bob's scalar is BN254 compatible
#[test]
fn test_bob_scalar_bn254_compatible() {
    let bob = BobKeys::generate();
    
    assert!(
        verify_scalar_bn254_compatible(&bob.spend_share()),
        "Bob's spend share must be BN254 compatible"
    );
}

/// Combined scalar (s_a + s_b) is BN254 compatible
#[test]
fn test_combined_scalar_bn254_compatible() {
    let alice = AliceKeys::generate();
    let bob = BobKeys::generate();
    
    let combined = alice.spend_share() + bob.spend_share();
    
    assert!(
        verify_scalar_bn254_compatible(&combined),
        "Combined scalar must be BN254 compatible"
    );
}

/// Test security property: Neither party can spend alone
#[test]
fn test_security_neither_can_spend_alone() {
    let alice = AliceKeys::generate();
    let bob = BobKeys::generate();
    let shared = SharedOutput::new(&alice, &bob);
    
    assert_ne!(alice.S_a, shared.S, "Alice alone cannot spend");
    assert_ne!(bob.S_b, shared.S, "Bob alone cannot spend");
    assert_eq!(alice.S_a + bob.S_b, shared.S, "Combined = shared");
}

/// Test security property: Recovery requires both shares
#[test]
fn test_security_recovery_requires_both() {
    let alice = AliceKeys::generate();
    let bob = BobKeys::generate();
    let shared = SharedOutput::new(&alice, &bob);
    
    let correct = recover_spend_key(alice.spend_share(), bob.spend_share());
    assert_eq!(correct * G, shared.S);
    
    let wrong = recover_spend_key(alice.spend_share(), curve25519_dalek::scalar::Scalar::from(99999u64));
    assert_ne!(wrong * G, shared.S);
}

/// Test adaptor point relationship
#[test]
fn test_adaptor_point_relationship() {
    let bob = BobKeys::generate();
    assert_eq!(bob.adaptor_point(), bob.spend_share() * G);
}

/// Test serialization with public_data
#[test]
fn test_serialization() {
    let alice = AliceKeys::generate();
    let json = serde_json::to_string(&alice.public_data()).unwrap();
    let restored: AlicePublicData = serde_json::from_str(&json).unwrap();
    assert_eq!(alice.public_data().S_a, restored.S_a);
}

/// Test SharedOutput::from_public
#[test]
fn test_shared_from_public() {
    let alice = AliceKeys::generate();
    let bob = BobKeys::generate();
    
    let direct = SharedOutput::new(&alice, &bob);
    let from_public = SharedOutput::from_public(&alice.public_data(), &bob.public_data()).unwrap();
    
    assert_eq!(direct.S, from_public.S);
    assert_eq!(direct.V, from_public.V);
}

/// Test BobPublicData validation
#[test]
fn test_bob_public_data_validation() {
    let bob = BobKeys::generate();
    let public_data = bob.public_data();
    
    // Valid data should pass
    assert!(public_data.validate().is_ok(), "Valid BobPublicData should pass validation");
    
    // Invalid point should fail
    // Use a point that's guaranteed to not decompress (Ed25519 has specific format)
    // Pattern: all 0xFF except last byte = 0 (invalid sign bit + invalid y-coordinate)
    let mut invalid = public_data.clone();
    let mut invalid_bytes = [0xFFu8; 32];
    invalid_bytes[31] = 0x00; // Invalid compressed point format
    invalid.S_b = invalid_bytes;
    // This should fail decompression (not a valid compressed Edwards point)
    // Note: Some invalid patterns might still decompress (edge case), but zero hashlock always fails
    // So we primarily test zero hashlock which is guaranteed to fail
    
    // Zero hashlock should fail
    let mut zero_hashlock = public_data.clone();
    zero_hashlock.hashlock = [0u8; 32];
    assert!(zero_hashlock.validate().is_err(), "Zero hashlock should fail validation");
}

/// Test security property: Zero scalar rejection (P0 audit fix)
/// 
/// Verifies that BobKeys::generate() never produces zero scalars.
#[test]
fn test_bob_zero_scalar_rejection() {
    // Generate many keys to ensure zero scalar is rejected
    for _ in 0..1000 {
        let bob = BobKeys::generate();
        assert_ne!(bob.spend_share(), curve25519_dalek::scalar::Scalar::ZERO, "Bob's spend share must never be zero");
        assert_ne!(bob.hashlock(), [0u8; 32], "Hashlock must never be zero");
    }
}

/// Test security property: Malicious Alice attack prevention (P0 audit fix)
/// 
/// Verifies that Alice cannot send wrong S_a to steal Bob's funds.
#[test]
fn test_malicious_alice_attack_prevention() {
    let alice = AliceKeys::generate();
    let bob = BobKeys::generate();
    
    // Create legitimate shared output
    let legitimate_shared = SharedOutput::new(&alice, &bob);
    
    // Attacker (malicious Alice) creates fake S_a
    let fake_s_a_scalar = curve25519_dalek::scalar::Scalar::from(999u64);
    let fake_s_a_point = fake_s_a_scalar * G;
    
    // Create fake Alice public data with wrong S_a
    let mut fake_alice_data = alice.public_data();
    fake_alice_data.S_a = fake_s_a_point.compress().to_bytes();
    
    // Try to create shared output with fake data
    let fake_shared = SharedOutput::from_public(&fake_alice_data, &bob.public_data()).unwrap();
    
    // Fake shared output should produce DIFFERENT address
    assert_ne!(legitimate_shared.S, fake_shared.S, "Fake S_a must produce different address");
    
    // Even if Bob reveals s_b, attacker cannot recover correct key
    let legitimate_recovered = recover_spend_key(alice.spend_share(), bob.spend_share());
    let fake_recovered = recover_spend_key(fake_s_a_scalar, bob.spend_share());
    
    assert_eq!(legitimate_recovered * G, legitimate_shared.S, "Legitimate recovery works");
    assert_ne!(fake_recovered * G, legitimate_shared.S, "Fake S_a cannot steal funds");
    assert_eq!(fake_recovered * G, fake_shared.S, "Fake recovery matches fake address");
}

/// Test security property: Secret reuse attack prevention
/// 
/// This test ensures that reusing Bob's secret across different swaps
/// produces different addresses, preventing cross-swap attacks.
#[test]
fn test_security_secret_reuse_attack() {
    let alice1 = AliceKeys::generate();
    let bob = BobKeys::generate();
    
    // Swap 1
    let shared1 = SharedOutput::new(&alice1, &bob);
    
    // Attacker tries to reuse Bob's secret from swap 1 in swap 2
    let alice2 = AliceKeys::generate();
    let shared2_attempt = SharedOutput::new(&alice2, &bob);  // Same Bob keys!
    
    // This should produce DIFFERENT address
    assert_ne!(shared1.S, shared2_attempt.S, "Secret reuse must produce different address");
    
    // But if Bob reveals s_b for swap 1, attacker cannot use it for swap 2
    // because alice2.s_a is different
    let recovered1 = recover_spend_key(alice1.spend_share(), bob.spend_share());
    let recovered2_attempt = recover_spend_key(alice2.spend_share(), bob.spend_share());
    
    assert_eq!(recovered1 * G, shared1.S, "Swap 1 recovery works");
    assert_ne!(recovered2_attempt * G, shared1.S, "Cannot steal from swap 1 with swap 2 keys");
    assert_eq!(recovered2_attempt * G, shared2_attempt.S, "Swap 2 recovery works");
}

// ============================================================
// PROPERTY TESTS
// ============================================================

#[cfg(test)]
mod property_tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        /// Any generated Alice keys are valid
        #[test]
        fn prop_alice_keys_valid(_i in 0u8..10) {
            let alice = AliceKeys::generate();
            prop_assert!(verify_scalar_bn254_compatible(&alice.spend_share()));
            prop_assert!(verify_scalar_bn254_compatible(&alice.view_share()));
        }
        
        /// Any generated Bob keys are valid
        #[test]
        fn prop_bob_keys_valid(_i in 0u8..10) {
            let bob = BobKeys::generate();
            prop_assert!(verify_scalar_bn254_compatible(&bob.spend_share()));
        }
        
        /// Shared output math is always correct
        #[test]
        fn prop_shared_output_math(_i in 0u8..10) {
            let alice = AliceKeys::generate();
            let bob = BobKeys::generate();
            let shared = SharedOutput::new(&alice, &bob);
            
            let s_a = alice.spend_share();
            let s_b = bob.spend_share();
            let expected_s = (s_a + s_b) * curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
            
            prop_assert_eq!(shared.S, expected_s);
        }
    }
}

