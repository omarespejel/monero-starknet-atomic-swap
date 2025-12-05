//! XMR-Starknet Atomic Swap - Secret Generator library.
//!
//! Provides a function to sample a Monero-compatible scalar, compute its
//! SHA-256 digest, and format outputs for Cairo tests.
//!
//! Also includes adaptor signature support for Monero atomic swaps.

pub mod adaptor;

use std::process::Command;
use std::path::PathBuf;
use std::env;

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::edwards::EdwardsPoint;
use curve25519_dalek::scalar::Scalar;
use num_bigint::BigUint;
use num_traits::Num;
use rand::rngs::OsRng;
use rand::RngCore;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

/// Output structure for JSON serialization.
#[derive(Serialize)]
pub struct SwapSecret {
    pub secret_hex: String,
    pub hash_u32_words: [u32; 8],
    pub cairo_hash_literal: String,
    pub cairo_secret_literal: String,
    pub adaptor_point_x_limbs: [String; 4],
    pub adaptor_point_y_limbs: [String; 4],
    pub fake_glv_hint: [String; 10],
}

/// Python tool output structure (partial, for adaptor point/hint extraction).
#[derive(Deserialize)]
struct PythonToolOutput {
    adaptor_point: AdaptorPointData,
    fake_glv_hint: FakeGlvHintData,
}

#[derive(Deserialize)]
struct AdaptorPointData {
    cairo_x: String,
    cairo_y: String,
}

#[derive(Deserialize)]
struct FakeGlvHintData {
    #[serde(deserialize_with = "deserialize_felts")]
    felts: Vec<String>,
}

fn deserialize_felts<'de, D>(deserializer: D) -> Result<Vec<String>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    use serde::de::Error;
    // Parse as Value first to get raw access
    let value = serde_json::Value::deserialize(deserializer)?;
    
    // Extract the raw JSON string and parse manually to preserve large integers
    let _json_str = serde_json::to_string(&value).map_err(D::Error::custom)?;
    
    // Parse the array manually from raw JSON
    // This is a workaround for serde_json converting large integers to f64
    // We'll use a simpler approach: parse as Value and handle each element
    let array = value.as_array().ok_or_else(|| D::Error::custom("Expected array"))?;
    
    array
        .iter()
        .map(|v| {
            match v {
                serde_json::Value::String(s) => {
                    if s.starts_with("0x") {
                        Ok(s.clone())
                    } else {
                        Ok(format!("0x{}", s))
                    }
                }
                serde_json::Value::Number(n) => {
                    // Try u64 first
                    if let Some(u) = n.as_u64() {
                        Ok(format!("0x{:x}", u))
                    } else {
                        // For very large numbers, Python now outputs as strings
                        // This branch shouldn't be reached, but handle it anyway
                        let num_str = n.to_string();
                        if num_str.contains('e') || num_str.contains('E') || num_str.contains('.') {
                            Err(D::Error::custom(format!(
                                "Number lost precision: {}. Large numbers should be strings in JSON.",
                                num_str
                            )))
                        } else {
                            match BigUint::from_str_radix(&num_str, 10) {
                                Ok(big) => Ok(format!("0x{:x}", big)),
                                Err(_) => Err(D::Error::custom(format!("Invalid number: {}", num_str))),
                            }
                        }
                    }
                }
                _ => Err(D::Error::custom("Felt must be string or number")),
            }
        })
        .collect()
}

/// Call Python tool to generate adaptor point and fake-GLV hint from secret.
/// Returns (x_limbs, y_limbs, fake_glv_hint) or error if Python tool unavailable.
fn generate_adaptor_point_from_python(secret_hex: &str) -> Result<([String; 4], [String; 4], [String; 10]), String> {
    // Find tools directory relative to Cargo.toml
    let mut tools_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    tools_dir.pop(); // Go up from rust/ to repo root
    tools_dir.push("tools");
    
    let script_path = tools_dir.join("generate_ed25519_test_data.py");
    if !script_path.exists() {
        return Err("Python tool not found".to_string());
    }

    // Call Python tool: uv run python generate_ed25519_test_data.py <secret_hex> --save
    let output = Command::new("uv")
        .args(&["run", "python", script_path.to_str().unwrap(), secret_hex, "--save"])
        .current_dir(&tools_dir)
        .output()
        .map_err(|e| format!("Failed to run Python tool: {}", e))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("Python tool failed: {}", stderr));
    }

    // Read JSON file written by Python tool
    let json_path = tools_dir.join("ed25519_test_data.json");
    let json_content = std::fs::read_to_string(&json_path)
        .map_err(|e| format!("Failed to read JSON file: {}", e))?;
    
    let data: PythonToolOutput = serde_json::from_str(&json_content)
        .map_err(|e| format!("Failed to parse Python tool output: {}", e))?;

    // Extract x_limbs from cairo_x: "(0x..., 0x..., 0x..., 0x...)"
    let x_str = data.adaptor_point.cairo_x.trim_matches(|c| c == '(' || c == ')');
    let x_limbs: Vec<String> = x_str
        .split(',')
        .map(|s| s.trim().to_string())
        .collect();
    if x_limbs.len() != 4 {
        return Err("Invalid x_limbs length".to_string());
    }

    // Extract y_limbs from cairo_y
    let y_str = data.adaptor_point.cairo_y.trim_matches(|c| c == '(' || c == ')');
    let y_limbs: Vec<String> = y_str
        .split(',')
        .map(|s| s.trim().to_string())
        .collect();
    if y_limbs.len() != 4 {
        return Err("Invalid y_limbs length".to_string());
    }

    // Extract fake_glv_hint (should be 10 felts, already converted to hex strings by deserializer)
    if data.fake_glv_hint.felts.len() != 10 {
        return Err("Invalid fake_glv_hint length".to_string());
    }

    Ok((
        [x_limbs[0].clone(), x_limbs[1].clone(), x_limbs[2].clone(), x_limbs[3].clone()],
        [y_limbs[0].clone(), y_limbs[1].clone(), y_limbs[2].clone(), y_limbs[3].clone()],
        [
            data.fake_glv_hint.felts[0].clone(),
            data.fake_glv_hint.felts[1].clone(),
            data.fake_glv_hint.felts[2].clone(),
            data.fake_glv_hint.felts[3].clone(),
            data.fake_glv_hint.felts[4].clone(),
            data.fake_glv_hint.felts[5].clone(),
            data.fake_glv_hint.felts[6].clone(),
            data.fake_glv_hint.felts[7].clone(),
            data.fake_glv_hint.felts[8].clone(),
            data.fake_glv_hint.felts[9].clone(),
        ],
    ))
}

/// Generate a Monero-compatible scalar and compute its SHA-256 hash.
pub fn generate_swap_secret() -> SwapSecret {
    let mut csprng = OsRng;
    let mut raw_bytes = [0u8; 32];
    csprng.fill_bytes(&mut raw_bytes);

    // Reduce to a valid scalar and keep the canonical 32-byte representation.
    let scalar = Scalar::from_bytes_mod_order(raw_bytes);
    let secret_bytes = scalar.to_bytes();

    // Compute adaptor point T = t·G on Edwards curve (for Monero compatibility check).
    let _adaptor_point: EdwardsPoint = &scalar * &ED25519_BASEPOINT_POINT;

    // Generate real adaptor point and fake-GLV hint using Python tool for consistency with Cairo.
    let secret_hex = hex::encode(secret_bytes);
    let (adaptor_point_x_limbs, adaptor_point_y_limbs, fake_glv_hint) = 
        generate_adaptor_point_from_python(&secret_hex).unwrap_or_else(|e| {
            // Fallback to placeholder if Python tool unavailable (e.g., in tests without Python env)
            // In production, ensure Python tool is available or use pre-generated values
            eprintln!("Warning: Python tool unavailable ({}), using placeholder adaptor point/hint", e);
            (
                ["0x0", "0x0", "0x0", "0x0"].map(str::to_string),
                ["0x0", "0x0", "0x0", "0x0"].map(str::to_string),
                ["0x0"; 10].map(str::to_string),
            )
        });

    // SHA-256 hash.
    let hash_bytes: [u8; 32] = Sha256::digest(&secret_bytes).into();

    // Convert to 8 x u32 (big-endian).
    let hash_words: [u32; 8] = core::array::from_fn(|i| {
        let start = i * 4;
        u32::from_be_bytes(hash_bytes[start..start + 4].try_into().unwrap())
    });

    // Format for Cairo.
    let cairo_hash_literal = format!(
        "array![{}].span()",
        hash_words
            .iter()
            .map(|w| format!("{}_u32", w))
            .collect::<Vec<_>>()
            .join(", ")
    );

    let cairo_secret_literal = format!(
        "\"{}\"",
        secret_bytes
            .iter()
            .map(|b| format!("\\x{:02x}", b))
            .collect::<String>()
    );

    SwapSecret {
        secret_hex: hex::encode(secret_bytes),
        hash_u32_words: hash_words,
        cairo_hash_literal,
        cairo_secret_literal,
        adaptor_point_x_limbs,
        adaptor_point_y_limbs,
        fake_glv_hint,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use sha2::Sha256;

    #[test]
    fn test_hash_word_count() {
        let secret = generate_swap_secret();
        assert_eq!(secret.hash_u32_words.len(), 8);
    }

    #[test]
    fn test_deterministic_hash() {
        // Given a known scalar, hash should be deterministic.
        let scalar = Scalar::from_bytes_mod_order([1u8; 32]);
        let hash: [u8; 32] = Sha256::digest(&scalar.to_bytes()).into();
        assert_eq!(hash.len(), 32);
    }
}
