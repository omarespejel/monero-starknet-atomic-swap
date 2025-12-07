//! Generate sqrt hints for all compressed Edwards points in test vectors.
//!
//! This uses curve25519-dalek to decompress points and extract x-coordinates
//! via Montgomery form, which matches what Garaga expects.

use curve25519_dalek::edwards::CompressedEdwardsY;
use serde_json::json;
use std::fs;

fn main() {
    // Read test vectors
    let test_vectors_path = "test_vectors.json";
    let test_vectors_json =
        fs::read_to_string(test_vectors_path).expect("Failed to read test_vectors.json");

    let mut test_vectors: serde_json::Value =
        serde_json::from_str(&test_vectors_json).expect("Failed to parse test_vectors.json");

    // Points to process
    let point_keys = vec![
        "adaptor_point_compressed",
        "second_point_compressed",
        "r1_compressed",
        "r2_compressed",
    ];

    println!("{}", "=".repeat(80));
    println!("Generating sqrt hints for all compressed Edwards points");
    println!("{}", "=".repeat(80));
    println!();

    // Collect hints first, then update JSON
    let mut hints: Vec<(String, String, u128, u128)> = Vec::new();

    for key in &point_keys {
        let compressed_hex = test_vectors[key]
            .as_str()
            .expect(&format!("{} not found", key))
            .to_string();

        // Convert hex to bytes
        let bytes: [u8; 32] = hex::decode(&compressed_hex)
            .expect("Invalid hex")
            .try_into()
            .expect("Must be 32 bytes");

        // Decompress point
        let compressed = CompressedEdwardsY(bytes);
        let point = compressed
            .decompress()
            .expect(&format!("Failed to decompress {}", key));

        // Get x-coordinate via Montgomery form
        let montgomery = point.to_montgomery();
        let x_bytes = montgomery.to_bytes();

        // Convert to u256 format (low/high u128)
        let x_low = u128::from_le_bytes(x_bytes[..16].try_into().unwrap());
        let x_high = u128::from_le_bytes(x_bytes[16..].try_into().unwrap());

        let hint_key = key.replace("_compressed", "_sqrt_hint");
        hints.push((hint_key.clone(), compressed_hex.clone(), x_low, x_high));

        println!("{}:", key);
        println!("  Compressed: {}", compressed_hex);
        println!("  sqrt_hint.low:  0x{:032x}", x_low);
        println!("  sqrt_hint.high: 0x{:032x}", x_high);
        println!();
    }

    // Now update test vectors
    for (hint_key, _, x_low, x_high) in &hints {
        test_vectors[hint_key] = json!(format!("{:064x}{:064x}", x_high, x_low));
        test_vectors[format!("{}_u256", hint_key)] = json!({
            "low": format!("0x{:032x}", x_low),
            "high": format!("0x{:032x}", x_high),
        });
    }

    // Write updated test vectors
    fs::write(
        test_vectors_path,
        serde_json::to_string_pretty(&test_vectors).unwrap(),
    )
    .expect("Failed to write test_vectors.json");

    println!("✅ Updated test_vectors.json with all sqrt hints");
    println!();
    println!("Cairo u256 format:");
    for key in &point_keys {
        let hint_key = key.replace("_compressed", "_sqrt_hint_u256");
        if let Some(hint) = test_vectors.get(&hint_key) {
            println!(
                "  {}_SQRT_HINT: u256 {{",
                key.to_uppercase().replace("_COMPRESSED", "")
            );
            println!("    low: {},", hint["low"].as_str().unwrap());
            println!("    high: {},", hint["high"].as_str().unwrap());
            println!("  }}");
        }
    }
}
