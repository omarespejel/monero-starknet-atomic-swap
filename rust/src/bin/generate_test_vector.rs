//! Generate single test vector with complete DLEQ proof data
//! Outputs JSON that Cairo can parse directly for deployment

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::scalar::Scalar;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::ops::Deref;
use zeroize::Zeroizing;
use xmr_secret_gen::dleq::generate_dleq_proof;

fn main() {
    // Generate secret (using test vector secret for reproducibility)
    let secret_bytes = [0x12u8; 32];
    let secret = Scalar::from_bytes_mod_order(secret_bytes);
    let secret_zeroizing = Zeroizing::new(secret);

    // Generate hashlock H = SHA-256(raw_secret_bytes)
    // CRITICAL: Cairo uses SHA-256(raw_secret_bytes) in verify_and_unlock
    // So the hashlock must match: SHA-256(secret_bytes), not SHA-256(scalar.to_bytes())
    let hashlock: [u8; 32] = Sha256::digest(secret_bytes).into();

    // Generate adaptor point T = t·G
    let adaptor_point = ED25519_BASEPOINT_POINT * *secret_zeroizing;

    // Generate DLEQ proof (uses raw bytes hashlock to match Cairo)
    let proof = generate_dleq_proof(&secret_zeroizing, &secret_bytes, &adaptor_point, &hashlock)
        .expect("Proof generation should succeed for valid inputs");

    // Convert to Cairo format (includes compressed points and sqrt hints)
    let cairo_format = proof.to_cairo_format(&adaptor_point);

    // Create complete test vector JSON
    let output = json!({
        "description": "Complete DLEQ proof test vector for deployment",
        "secret": hex::encode(secret_bytes),
        "hashlock": hex::encode(hashlock),
        "adaptor_point_compressed": hex::encode(cairo_format.adaptor_point_compressed),
        "adaptor_point_sqrt_hint": hex::encode(cairo_format.adaptor_point_sqrt_hint),
        "dleq_second_point_compressed": hex::encode(cairo_format.second_point_compressed),
        "second_point_sqrt_hint": hex::encode(cairo_format.second_point_sqrt_hint),
        "challenge": hex::encode(cairo_format.challenge),
        "response": hex::encode(cairo_format.response),
        "g_compressed": hex::encode(cairo_format.g_compressed),
        "y_compressed": hex::encode(cairo_format.y_compressed),
        "r1_compressed": hex::encode(cairo_format.r1_compressed),
        "r2_compressed": hex::encode(cairo_format.r2_compressed),
        "expected_verification": true,
        "notes": "Complete test vector with all DLEQ proof data needed for deployment"
    });

    println!("{}", serde_json::to_string_pretty(&output).unwrap());
}
