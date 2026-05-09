//! Generate the second generator point Y for DLEQ proofs.
//!
//! Outputs the domain-separated DLEQ second generator used by Rust and Cairo.

use xmr_secret_gen::dleq::get_second_generator;

fn main() {
    let y_edwards = get_second_generator();
    let compressed = y_edwards.compress().to_bytes();

    println!("Edwards Point Y:");
    println!("  Compressed bytes: {:?}", compressed);
    println!("  Compressed hex: {}", hex::encode(compressed));
    println!("  Sign bit: {}", compressed[31] & 0x80 != 0);

    println!("\nTo get Weierstrass coordinates for Cairo:");
    println!("1. Regenerate rust/test_vectors.json");
    println!("2. Run: uv run --project tools python tools/regenerate_dleq_hints.py");
    println!("3. Use cairo/generated_dleq_vectors.json second_generator limbs");
}
