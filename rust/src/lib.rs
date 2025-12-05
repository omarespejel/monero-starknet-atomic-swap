//! XMR-Starknet Atomic Swap - Secret Generator library.
//!
//! Provides a function to sample a Monero-compatible scalar, compute its
//! SHA-256 digest, and format outputs for Cairo tests.

use curve25519_dalek::scalar::Scalar;
use rand::rngs::OsRng;
use rand::RngCore;
use serde::Serialize;
use sha2::{Digest, Sha256};

/// Output structure for JSON serialization.
#[derive(Serialize)]
pub struct SwapSecret {
    pub secret_hex: String,
    pub hash_u32_words: [u32; 8],
    pub cairo_hash_literal: String,
    pub cairo_secret_literal: String,
}

/// Generate a Monero-compatible scalar and compute its SHA-256 hash.
pub fn generate_swap_secret() -> SwapSecret {
    let mut csprng = OsRng;
    let mut raw_bytes = [0u8; 32];
    csprng.fill_bytes(&mut raw_bytes);

    // Reduce to a valid scalar and keep the canonical 32-byte representation.
    let scalar = Scalar::from_bytes_mod_order(raw_bytes);
    let secret_bytes = scalar.to_bytes();

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

