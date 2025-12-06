/// Generate sqrt hints for R1 and R2 commitment points from test vectors.
///
/// This binary reads test_vectors.json and generates sqrt hints (x-coordinates)
/// for R1 and R2 points, which are needed for Cairo point decompression.

use curve25519_dalek::edwards::CompressedEdwardsY;
use std::fs;

fn main() {
    // Read test vectors
    let test_vectors_path = "test_vectors.json";
    let test_vectors_json = fs::read_to_string(test_vectors_path)
        .expect("Failed to read test_vectors.json");
    
    let test_vectors: serde_json::Value = serde_json::from_str(&test_vectors_json)
        .expect("Failed to parse test_vectors.json");
    
    // Extract compressed Edwards points (hex strings)
    let r1_compressed_hex = test_vectors["r1_compressed"]
        .as_str()
        .expect("r1_compressed not found");
    let r2_compressed_hex = test_vectors["r2_compressed"]
        .as_str()
        .expect("r2_compressed not found");
    
    // Convert hex strings to compressed Edwards points
    let r1_bytes: [u8; 32] = hex::decode(r1_compressed_hex)
        .expect("Invalid R1 hex")
        .try_into()
        .expect("R1 must be 32 bytes");
    let r2_bytes: [u8; 32] = hex::decode(r2_compressed_hex)
        .expect("Invalid R2 hex")
        .try_into()
        .expect("R2 must be 32 bytes");
    
    let r1_compressed = CompressedEdwardsY(r1_bytes);
    let r2_compressed = CompressedEdwardsY(r2_bytes);
    
    // Decompress to get full Edwards points
    let r1_point = r1_compressed.decompress().expect("Failed to decompress R1");
    let r2_point = r2_compressed.decompress().expect("Failed to decompress R2");
    
    // Extract x-coordinates (sqrt hints) via Montgomery form
    let r1_montgomery = r1_point.to_montgomery();
    let r2_montgomery = r2_point.to_montgomery();
    
    let r1_x_bytes = r1_montgomery.to_bytes();
    let r2_x_bytes = r2_montgomery.to_bytes();
    
    // Convert to u256 format (low/high u128)
    let r1_x_low = u128::from_le_bytes(r1_x_bytes[..16].try_into().unwrap());
    let r1_x_high = u128::from_le_bytes(r1_x_bytes[16..].try_into().unwrap());
    
    let r2_x_low = u128::from_le_bytes(r2_x_bytes[..16].try_into().unwrap());
    let r2_x_high = u128::from_le_bytes(r2_x_bytes[16..].try_into().unwrap());
    
    // Print Cairo-compatible format
    println!("// Sqrt hints for R1 and R2 (x-coordinates)");
    println!("// Generated from test_vectors.json");
    println!();
    println!("const TEST_R1_SQRT_HINT: u256 = u256 {{");
    println!("    low: 0x{:x}," , r1_x_low);
    println!("    high: 0x{:x}," , r1_x_high);
    println!("}};");
    println!();
    println!("const TEST_R2_SQRT_HINT: u256 = u256 {{");
    println!("    low: 0x{:x}," , r2_x_low);
    println!("    high: 0x{:x}," , r2_x_high);
    println!("}};");
    
    // Also update test_vectors.json with sqrt hints
    let mut test_vectors: serde_json::Map<String, serde_json::Value> = 
        serde_json::from_str(&test_vectors_json).unwrap();
    
    test_vectors.insert(
        "r1_sqrt_hint".to_string(),
        serde_json::Value::String(hex::encode(r1_x_bytes))
    );
    test_vectors.insert(
        "r2_sqrt_hint".to_string(),
        serde_json::Value::String(hex::encode(r2_x_bytes))
    );
    
    let updated_json = serde_json::to_string_pretty(&test_vectors).unwrap();
    fs::write(test_vectors_path, updated_json).expect("Failed to write test_vectors.json");
    
    println!();
    println!("✓ Updated test_vectors.json with r1_sqrt_hint and r2_sqrt_hint");
}

