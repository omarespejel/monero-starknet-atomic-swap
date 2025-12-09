//! Generate canonical test vectors with ALL intermediate values
//!
//! This is the SINGLE SOURCE OF TRUTH for test vectors.
//! Generated ONCE, validated by Cairo, never regenerated unless protocol changes.
//!
//! Includes all intermediate values for debugging cross-implementation issues.

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::scalar::Scalar;
use serde_json::json;
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;
use xmr_secret_gen::dleq::generate_dleq_proof;

fn main() {
    // Generate secret (using test vector secret for reproducibility)
    let secret_bytes = [0x12u8; 32];
    let secret = Scalar::from_bytes_mod_order(secret_bytes);
    let secret_zeroizing = Zeroizing::new(secret);
    let secret_scalar_bytes = secret.to_bytes();

    // Compute both hashlock methods for comparison
    let hashlock_of_raw: [u8; 32] = Sha256::digest(secret_bytes).into();
    let hashlock_of_scalar: [u8; 32] = Sha256::digest(secret_scalar_bytes).into();

    // Check if scalar reduction changed the bytes
    let scalar_reduction_changed = secret_bytes != secret_scalar_bytes;

    // Generate adaptor point T = t·G
    let adaptor_point = ED25519_BASEPOINT_POINT * *secret_zeroizing;

    // Generate DLEQ proof using canonical hashlock (raw bytes to match Cairo)
    let proof = generate_dleq_proof(
        &secret_zeroizing,
        &secret_bytes,
        &adaptor_point,
        &hashlock_of_raw,
    )
    .expect("Proof generation should succeed for valid inputs");

    // Convert to Cairo format
    let cairo_format = proof.to_cairo_format(&adaptor_point);

    // Create canonical test vector with ALL intermediate values
    let output = json!({
        "vector_version": "1.0.0",
        "description": "Canonical test vector - SINGLE SOURCE OF TRUTH",
        "protocol_note": "Cairo uses SHA-256(raw_secret_bytes) in verify_and_unlock",
        
        // Secret representations
        "secret_raw_bytes": hex::encode(secret_bytes),
        "secret_as_scalar_bytes": hex::encode(secret_scalar_bytes),
        "scalar_reduction_changed_bytes": scalar_reduction_changed,
        
        // Hashlock computations (both methods for comparison)
        "hashlock_of_raw": hex::encode(hashlock_of_raw),
        "hashlock_of_scalar": hex::encode(hashlock_of_scalar),
        "canonical_hashlock": hex::encode(hashlock_of_raw),
        "why_canonical": "Cairo uses raw bytes in verify_and_unlock - no scalar reduction",
        
        // DLEQ proof data
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
        "generated_by": "generate_canonical_test_vectors.rs",
        "audit_note": "This vector is the canonical reference. All implementations must match these values."
    });

    println!("{}", serde_json::to_string_pretty(&output).unwrap());
    
    // Print warning if scalar reduction changed bytes
    if scalar_reduction_changed {
        eprintln!("\n⚠️  WARNING: Scalar reduction changed bytes!");
        eprintln!("    Raw:    {}", hex::encode(secret_bytes));
        eprintln!("    Scalar: {}", hex::encode(secret_scalar_bytes));
        eprintln!("    Using raw bytes for hashlock (Cairo-compatible)");
    }
}

