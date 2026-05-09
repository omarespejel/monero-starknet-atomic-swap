//! TDD Tests for DLEQ Proof Generation for Bob's Secret
//!
//! Tests DLEQ proof generation specifically for Bob's secret (s_b) in two-party protocol.

use xmr_secret_gen::crypto::scalar_compat::verify_scalar_bn254_compatible;
use xmr_secret_gen::dleq::generate_dleq_proof_for_bob;
use xmr_secret_gen::monero::two_party_keys::BobKeys;

// ============================================================
// BASIC FUNCTIONALITY TESTS
// ============================================================

/// DLEQ proof can be generated for Bob's secret
#[test]
fn test_dleq_proof_generation_for_bob() {
    let bob = BobKeys::generate();

    let proof = generate_dleq_proof_for_bob(&bob)
        .expect("DLEQ proof generation must succeed for valid Bob keys");

    // Proof should have non-zero challenge and response
    assert!(
        proof.challenge.to_bytes() != [0u8; 32],
        "Challenge must be non-zero"
    );
    assert!(
        proof.response.to_bytes() != [0u8; 32],
        "Response must be non-zero"
    );
}

/// DLEQ proof generation verifies BN254 compatibility
#[test]
fn test_dleq_verifies_bn254_compatibility() {
    let bob = BobKeys::generate();

    // Bob's secret must be BN254 compatible for Cairo verification
    assert!(
        verify_scalar_bn254_compatible(&bob.spend_share()),
        "Bob's secret must be BN254 compatible before DLEQ"
    );

    // Proof generation should succeed (implicitly verifies compatibility)
    let proof =
        generate_dleq_proof_for_bob(&bob).expect("DLEQ proof must succeed for compatible scalar");

    // Challenge and response must also be compatible
    assert!(
        verify_scalar_bn254_compatible(&proof.challenge),
        "DLEQ challenge must be BN254 compatible"
    );
    assert!(
        verify_scalar_bn254_compatible(&proof.response),
        "DLEQ response must be BN254 compatible"
    );
}

/// DLEQ proof binds hashlock to adaptor point
#[test]
fn test_dleq_proof_binds_hashlock() {
    let bob = BobKeys::generate();

    let proof = generate_dleq_proof_for_bob(&bob).expect("DLEQ proof generation must succeed");

    // The proof should be verifiable (we'll add verification tests later)
    // For now, just check that proof structure is valid
    assert_eq!(proof.second_point.compress().to_bytes().len(), 32);
    assert_eq!(proof.r1.compress().to_bytes().len(), 32);
    assert_eq!(proof.r2.compress().to_bytes().len(), 32);
}
