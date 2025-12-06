//! Generate single test vector with correct compressed Edwards format
//! Outputs JSON that Cairo can parse directly

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::edwards::{CompressedEdwardsY, EdwardsPoint};
use curve25519_dalek::scalar::Scalar;
use sha2::{Digest, Sha256};
use serde_json::json;

/// Convert compressed Edwards point bytes to u256 format (Garaga-style)
/// 
/// Format: u256 { low: bytes[0..15], high: bytes[16..31] }
/// Both interpreted as little-endian (RFC 8032)
fn compressed_bytes_to_u256(bytes: [u8; 32]) -> serde_json::Value {
    // Interpret 32 bytes as little-endian integer (RFC 8032)
    let mut int_value_full = 0u128;
    for (i, &byte) in bytes.iter().enumerate() {
        if i < 16 {
            int_value_full |= (byte as u128) << (i * 8);
        }
    }
    
    let mut int_value_high = 0u128;
    for (i, &byte) in bytes.iter().enumerate().skip(16) {
        int_value_high |= (byte as u128) << ((i - 16) * 8);
    }
    
    // Split into low/high u128
    let low = int_value_full;
    let high = int_value_high;
    
    json!({
        "low": format!("0x{:x}", low),
        "high": format!("0x{:x}", high),
        "cairo_u256": format!("u256 {{ low: 0x{:x}, high: 0x{:x} }}", low, high),
    })
}

fn main() {
    // Generate secret
    let secret_bytes = [0x12u8; 32];  // Test vector from test_vectors.json
    let secret = Scalar::from_bytes_mod_order(secret_bytes);
    
    // Generate hashlock
    let hashlock: [u8; 32] = Sha256::digest(&secret_bytes).into();
    
    // Generate adaptor point T = t·G
    let T = ED25519_BASEPOINT_POINT * secret;
    
    // Compress point (RFC 8032 format: 32 bytes, little-endian)
    let T_compressed: CompressedEdwardsY = T.compress();
    let T_bytes: [u8; 32] = T_compressed.to_bytes();
    
    // Convert to u256 format
    let T_u256 = compressed_bytes_to_u256(T_bytes);
    
    // Output in format Python can parse
    let output = json!({
        "adaptor_point_compressed": hex::encode(T_bytes),
        "adaptor_point_compressed_u256": T_u256,
        "hashlock": hex::encode(hashlock),
        "secret": hex::encode(secret_bytes),
    });
    
    println!("{}", serde_json::to_string_pretty(&output).unwrap());
}

