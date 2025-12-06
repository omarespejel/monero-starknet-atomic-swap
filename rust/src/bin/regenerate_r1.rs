//! Regenerate R1 commitment point with guaranteed valid Ed25519 compression.
//!
//! This tool generates a fresh R1 point using proper Ed25519 point generation,
//! ensuring it can be decompressed correctly with twisted Edwards x-coordinates.

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::scalar::Scalar;
use serde_json::json;
use std::fs;

fn main() {
    // Read existing test vectors
    let test_vectors_path = "test_vectors.json";
    let test_vectors_json = fs::read_to_string(test_vectors_path)
        .expect("Failed to read test_vectors.json");
    
    let mut test_vectors: serde_json::Value = serde_json::from_str(&test_vectors_json)
        .expect("Failed to parse test_vectors.json");
    
    println!("{}", "=".repeat(80));
    println!("Regenerating R1 Commitment Point");
    println!("{}", "=".repeat(80));
    println!();
    
    // Extract k (nonce) from existing DLEQ proof or generate new one
    // For DLEQ: R1 = k·G, R2 = k·Y
    // We'll use a deterministic k based on the existing challenge/response
    
    // Get the existing challenge to derive k deterministically
    let challenge_hex = test_vectors["challenge"]
        .as_str()
        .expect("challenge not found");
    
    // Use challenge as seed for k (deterministic but different from original)
    // In practice, k should be random, but for test vectors we want determinism
    let k_bytes: [u8; 32] = {
        let mut bytes = [0u8; 32];
        let challenge_bytes = hex::decode(challenge_hex).expect("Invalid challenge hex");
        bytes[..32].copy_from_slice(&challenge_bytes[..32]);
        bytes
    };
    
    // Convert to scalar (reduce mod order)
    let k_scalar = Scalar::from_bytes_mod_order(k_bytes);
    
    // Generate R1 = k·G
    let g = ED25519_BASEPOINT_POINT;
    let r1_point = g * k_scalar;
    
    // Compress R1 properly
    let r1_compressed = r1_point.compress();
    let r1_bytes = r1_compressed.to_bytes();
    
    // Convert to hex
    let r1_hex = hex::encode(r1_bytes);
    
    println!("Generated R1:");
    println!("  Compressed: {}", r1_hex);
    println!("  Point: {:?}", r1_point);
    println!();
    
    // Verify it decompresses correctly
    let decompressed = r1_compressed.decompress()
        .expect("Failed to decompress newly generated R1");
    
    assert_eq!(decompressed, r1_point, "Decompression verification failed");
    println!("✓ R1 decompresses correctly");
    println!();
    
    // Update test vectors
    test_vectors["r1_compressed"] = json!(r1_hex);
    
    // Also update R2 = k·Y to maintain DLEQ consistency
    let y = g * Scalar::from(2u64); // Y = 2·G (matches current implementation)
    let r2_point = y * k_scalar;
    let r2_compressed = r2_point.compress();
    let r2_bytes = r2_compressed.to_bytes();
    let r2_hex = hex::encode(r2_bytes);
    
    println!("Updated R2 (for DLEQ consistency):");
    println!("  Compressed: {}", r2_hex);
    println!();
    
    test_vectors["r2_compressed"] = json!(r2_hex);
    
    // Write updated test vectors
    fs::write(test_vectors_path, serde_json::to_string_pretty(&test_vectors).unwrap())
        .expect("Failed to write test_vectors.json");
    
    println!("✅ Updated test_vectors.json with regenerated R1 and R2");
    println!();
    println!("Next steps:");
    println!("1. Run Python script to generate twisted Edwards sqrt hints");
    println!("2. Update Cairo test files with correct hints");
    println!("3. Run tests to verify decompression works");
}

