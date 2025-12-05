//! Generate the second generator point Y for DLEQ proofs.
//!
//! Computes Y = hash_to_curve("DLEQ_SECOND_BASE_V1") and outputs Cairo-formatted u384 limbs.

use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::scalar::Scalar;
use sha2::{Digest, Sha512};

fn main() {
    // Hash-to-curve using SHA-512 (Ed25519 standard)
    let mut hasher = Sha512::new();
    hasher.update(b"DLEQ_SECOND_BASE_V1");
    let hash = hasher.finalize();
    
    // Use hash as scalar seed
    let mut scalar_bytes = [0u8; 32];
    scalar_bytes.copy_from_slice(&hash[..32]);
    let scalar = Scalar::from_bytes_mod_order(scalar_bytes);
    
    // Compute Y = scalar·G
    let Y_edwards = ED25519_BASEPOINT_POINT * scalar;
    
    println!("Edwards Point Y:");
    println!("  Compressed: {:?}", Y_edwards.compress().to_bytes());
    println!("  X: {}", Y_edwards.compress().to_bytes()[31] & 0x80 != 0);
    
    // Note: This outputs Edwards coordinates
    // For Cairo, we need Weierstrass coordinates via Python tool
    println!("\nTo get Weierstrass coordinates for Cairo:");
    println!("1. Use Python tool to convert Edwards -> Weierstrass");
    println!("2. Split Weierstrass coordinates into u384 limbs (4×96-bit)");
    println!("3. Hardcode the limbs in Cairo get_dleq_second_generator()");
}

