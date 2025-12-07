//! Extract Ed25519 compressed point constants for Cairo.
//!
//! This binary outputs Cairo constants for G and Y compressed Edwards points.

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::scalar::Scalar;

fn main() {
    // G is the standard Ed25519 basepoint
    let G = ED25519_BASEPOINT_POINT;
    let g_compressed = G.compress().to_bytes();

    // Y = 2·G (matching current Rust implementation in dleq.rs)
    let Y = ED25519_BASEPOINT_POINT * Scalar::from(2u64);
    let y_compressed = Y.compress().to_bytes();

    // Convert to u256 format (little-endian bytes)
    let g_u256_low = u128::from_le_bytes(g_compressed[0..16].try_into().unwrap());
    let g_u256_high = u128::from_le_bytes(g_compressed[16..32].try_into().unwrap());

    let y_u256_low = u128::from_le_bytes(y_compressed[0..16].try_into().unwrap());
    let y_u256_high = u128::from_le_bytes(y_compressed[16..32].try_into().unwrap());

    // Format as u256 (little-endian)
    let g_low_lo = g_u256_low & 0xffffffffffffffff;
    let g_low_hi = (g_u256_low >> 64) & 0xffffffffffffffff;
    let g_high_lo = g_u256_high & 0xffffffffffffffff;
    let g_high_hi = (g_u256_high >> 64) & 0xffffffffffffffff;

    let y_low_lo = y_u256_low & 0xffffffffffffffff;
    let y_low_hi = (y_u256_low >> 64) & 0xffffffffffffffff;
    let y_high_lo = y_u256_high & 0xffffffffffffffff;
    let y_high_hi = (y_u256_high >> 64) & 0xffffffffffffffff;

    println!("// Ed25519 Base Point G (compressed)");
    println!("const ED25519_BASE_POINT_COMPRESSED: u256 = u256 {{");
    println!("    low: 0x{:016x}{:016x},", g_low_lo, g_low_hi);
    println!("    high: 0x{:016x}{:016x},", g_high_lo, g_high_hi);
    println!("}};");
    println!();
    println!("// Ed25519 Second Generator Y = 2·G (compressed)");
    println!("const ED25519_SECOND_GENERATOR_COMPRESSED: u256 = u256 {{");
    println!("    low: 0x{:016x}{:016x},", y_low_lo, y_low_hi);
    println!("    high: 0x{:016x}{:016x},", y_high_lo, y_high_hi);
    println!("}};");

    // Also print hex for verification
    println!("\n// G compressed (hex): {}", hex::encode(g_compressed));
    println!("// Y compressed (hex): {}", hex::encode(y_compressed));
}
