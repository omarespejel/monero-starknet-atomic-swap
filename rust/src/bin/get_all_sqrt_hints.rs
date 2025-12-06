
use curve25519_dalek::edwards::CompressedEdwardsY;
use serde_json::json;

fn main() {
    let test_vectors_path = "test_vectors.json";
    let test_vectors_json = std::fs::read_to_string(test_vectors_path).unwrap();
    let test_vectors: serde_json::Value = serde_json::from_str(&test_vectors_json).unwrap();
    
    let points = vec![
        ("adaptor_point", test_vectors["adaptor_point_compressed"].as_str().unwrap()),
        ("second_point", test_vectors["second_point_compressed"].as_str().unwrap()),
        ("r1", test_vectors["r1_compressed"].as_str().unwrap()),
        ("r2", test_vectors["r2_compressed"].as_str().unwrap()),
    ];
    
    let mut result = json!({});
    
    for (name, hex_str) in points {
        let bytes: [u8; 32] = hex::decode(hex_str).unwrap().try_into().unwrap();
        let compressed = CompressedEdwardsY(bytes);
        let point = compressed.decompress().unwrap();
        let montgomery = point.to_montgomery();
        let x_bytes = montgomery.to_bytes();
        
        let low = u128::from_le_bytes(x_bytes[..16].try_into().unwrap());
        let high = u128::from_le_bytes(x_bytes[16..].try_into().unwrap());
        
        result[format!("{}_sqrt_hint", name)] = json!({
            "low": format!("0x{:x}", low),
            "high": format!("0x{:x}", high),
        });
    }
    
    println!("{}", serde_json::to_string_pretty(&result).unwrap());
}
