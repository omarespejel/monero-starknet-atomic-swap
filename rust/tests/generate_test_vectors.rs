//! Generate test vectors for all three test suites
//!
//! Run: cargo test --test generate_test_vectors -- --ignored --nocapture

use serde_json::json;
use sha2::{Digest, Sha256};
use std::fs;

use xmr_secret_gen::crypto::scalar_compat::ed25519_scalar_to_bn254_bytes;
use xmr_secret_gen::dleq::generate_dleq_proof_for_bob;
use xmr_secret_gen::monero::two_party_keys::{AliceKeys, BobKeys, SharedOutput};

/// Generate two-party test vectors
#[test]
#[ignore] // Run manually: cargo test generate_two_party -- --ignored
fn generate_two_party_vectors() {
    let mut vectors = Vec::new();

    for i in 0..5 {
        let alice = AliceKeys::generate();
        let bob = BobKeys::generate();
        let shared = SharedOutput::new(&alice, &bob);

        let vector = json!({
            "test_id": format!("two_party_{}", i),
            "alice": {
                "s_a": hex::encode(alice.spend_share().to_bytes()),
                "v_a": hex::encode(alice.view_share().to_bytes()),
                "S_a_compressed": hex::encode(alice.S_a.compress().to_bytes()),
                "V_a_compressed": hex::encode(alice.V_a.compress().to_bytes()),
            },
            "bob": {
                "s_b": hex::encode(bob.spend_share().to_bytes()),
                "v_b": hex::encode(bob.view_share().to_bytes()),
                "S_b_compressed": hex::encode(bob.S_b.compress().to_bytes()),
                "V_b_compressed": hex::encode(bob.V_b.compress().to_bytes()),
                "hashlock": hex::encode(bob.hashlock()),
                "adaptor_point": hex::encode(bob.adaptor_point().compress().to_bytes()),
                "bn254_scalar": hex::encode(ed25519_scalar_to_bn254_bytes(&bob.spend_share())),
            },
            "shared": {
                "S_combined": hex::encode(shared.S.compress().to_bytes()),
                "V_combined": hex::encode(shared.V.compress().to_bytes()),
                "v_combined": hex::encode(shared.v.to_bytes()),
            },
            "verification": {
                "s_full": hex::encode((alice.spend_share() + bob.spend_share()).to_bytes()),
            }
        });

        vectors.push(vector);
    }

    let output = json!({
        "description": "Two-party key generation test vectors",
        "version": "1.0.0",
        "generated_at": chrono::Utc::now().to_rfc3339(),
        "vectors": vectors,
    });

    fs::write(
        "tests/fixtures/protocol/two_party_key_exchange_vectors.json",
        serde_json::to_string_pretty(&output).unwrap(),
    )
    .expect("Failed to write vectors");

    println!("✅ Generated {} two-party test vectors", vectors.len());
}

/// Generate integration test vectors
#[test]
#[ignore]
fn generate_integration_vectors() {
    let alice = AliceKeys::generate();
    let bob = BobKeys::generate();
    let shared = SharedOutput::new(&alice, &bob);

    let dleq_proof = generate_dleq_proof_for_bob(&bob).expect("DLEQ proof must succeed");

    let scenario = json!({
        "scenario": "happy_path_swap",
        "phases": {
            "1_key_exchange": {
                "alice_public": {
                    "S_a": hex::encode(alice.S_a.compress().to_bytes()),
                    "V_a": hex::encode(alice.V_a.compress().to_bytes()),
                    "v_a": hex::encode(alice.view_share().to_bytes()),
                },
                "bob_public": {
                    "S_b": hex::encode(bob.S_b.compress().to_bytes()),
                    "V_b": hex::encode(bob.V_b.compress().to_bytes()),
                    "v_b": hex::encode(bob.view_share().to_bytes()),
                    "hashlock": hex::encode(bob.hashlock()),
                },
                "shared_address": hex::encode(shared.S.compress().to_bytes()),
            },
            "2_contract_deploy": {
                "hashlock": hex::encode(bob.hashlock()),
                "adaptor_point": hex::encode(bob.adaptor_point().compress().to_bytes()),
                "dleq_challenge": hex::encode(dleq_proof.challenge.to_bytes()),
                "dleq_response": hex::encode(dleq_proof.response.to_bytes()),
            },
            "3_xmr_lock": {
                "recipient_address": hex::encode(shared.S.compress().to_bytes()),
                "view_key": hex::encode(shared.v.to_bytes()),
            },
            "4_secret_reveal": {
                "s_b": hex::encode(bob.spend_share().to_bytes()),
                "hashlock_preimage": hex::encode(bob.secret_bytes()),
            },
            "5_xmr_claim": {
                "recovered_key": hex::encode((alice.spend_share() + bob.spend_share()).to_bytes()),
            }
        }
    });

    let output = json!({
        "description": "Full swap protocol end-to-end test vectors",
        "version": "1.0.0",
        "generated_at": chrono::Utc::now().to_rfc3339(),
        "scenarios": [scenario],
    });

    fs::write(
        "tests/fixtures/integration/full_swap_protocol_vectors.json",
        serde_json::to_string_pretty(&output).unwrap(),
    )
    .expect("Failed to write vectors");

    println!("✅ Generated integration test vectors");
}
