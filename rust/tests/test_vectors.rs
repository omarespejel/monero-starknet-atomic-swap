//! Generate cross-platform test vectors for Rust↔Cairo BLAKE2s compatibility.
//!
//! This module generates test vectors that can be used in both Rust and Cairo
//! to verify that BLAKE2s challenge computation produces identical results.

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::edwards::EdwardsPoint;
use curve25519_dalek::scalar::Scalar;
use serde_json::json;
use std::fs;
use xmr_secret_gen::dleq::{generate_dleq_proof, DleqProof};

/// Generate test vectors for Cairo integration tests
#[test]
#[ignore] // Run manually: cargo test --test test_vectors -- --ignored
fn generate_cairo_test_vectors() {
    // Generate a deterministic secret for reproducible test vectors
    let secret_bytes = [0x12; 32];
    let secret = Scalar::from_bytes_mod_order(secret_bytes);

    // Generate adaptor point
    let adaptor_point = ED25519_BASEPOINT_POINT * secret;

    // Generate hashlock (SHA-256 of "test_hashlock")
    let hashlock = [
        0xd7, 0x8e, 0x35, 0x02, 0x10, 0x8c, 0x5b, 0x5a,
        0x5c, 0x90, 0x2f, 0x24, 0x72, 0x5c, 0xe1, 0x5e,
        0x14, 0xab, 0x8e, 0x41, 0x1b, 0x93, 0x28, 0x5f,
        0x9c, 0x5b, 0x14, 0x05, 0xf1, 0x1d, 0xca, 0x4d,
    ];

    // Generate DLEQ proof
    let proof = generate_dleq_proof(&secret, &adaptor_point, &hashlock);

    // Convert to Cairo format
    let cairo_format = proof.to_cairo_format(&adaptor_point);

    // Create test vector JSON
    let test_vector = json!({
        "description": "DLEQ proof test vector for Rust↔Cairo compatibility",
        "secret": hex::encode(secret_bytes),
        "hashlock": hex::encode(hashlock),
        "adaptor_point_compressed": hex::encode(cairo_format.adaptor_point_compressed),
        "adaptor_point_sqrt_hint": hex::encode(cairo_format.adaptor_point_sqrt_hint),
        "second_point_compressed": hex::encode(cairo_format.second_point_compressed),
        "second_point_sqrt_hint": hex::encode(cairo_format.second_point_sqrt_hint),
        "challenge": hex::encode(cairo_format.challenge),
        "response": hex::encode(cairo_format.response),
        "g_compressed": hex::encode(cairo_format.g_compressed),
        "y_compressed": hex::encode(cairo_format.y_compressed),
        "r1_compressed": hex::encode(cairo_format.r1_compressed),
        "r2_compressed": hex::encode(cairo_format.r2_compressed),
        "expected_verification": true,
        "notes": "This test vector can be used in Cairo tests to verify BLAKE2s compatibility"
    });

    // Write to file
    let output_path = "test_vectors.json";
    fs::write(output_path, serde_json::to_string_pretty(&test_vector).unwrap())
        .expect("Failed to write test vectors");

    println!("✅ Test vectors written to {}", output_path);
    println!("📋 Use this file in Cairo integration tests");
}

/// Generate multiple test vectors with different inputs
#[test]
#[ignore]
fn generate_multiple_test_vectors() {
    let mut test_vectors = Vec::new();

    // Generate test vectors with different secrets
    for i in 0..5 {
        let secret_bytes = [i as u8; 32];
        let secret = Scalar::from_bytes_mod_order(secret_bytes);
        let adaptor_point = ED25519_BASEPOINT_POINT * secret;

        // Use different hashlock for each test
        let mut hashlock = [0u8; 32];
        hashlock[0] = i as u8;

        let proof = generate_dleq_proof(&secret, &adaptor_point, &hashlock);
        let cairo_format = proof.to_cairo_format(&adaptor_point);

        test_vectors.push(json!({
            "test_id": i,
            "adaptor_point_compressed": hex::encode(cairo_format.adaptor_point_compressed),
            "challenge": hex::encode(cairo_format.challenge),
            "response": hex::encode(cairo_format.response),
            "r1_compressed": hex::encode(cairo_format.r1_compressed),
            "r2_compressed": hex::encode(cairo_format.r2_compressed),
        }));
    }

    let output = json!({
        "test_vectors": test_vectors,
        "count": test_vectors.len(),
    });

    fs::write(
        "test_vectors_multiple.json",
        serde_json::to_string_pretty(&output).unwrap(),
    )
    .expect("Failed to write test vectors");

    println!("✅ Generated {} test vectors", test_vectors.len());
}

