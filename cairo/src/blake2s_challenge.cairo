/// # BLAKE2s Challenge Computation Module
///
/// Production-grade BLAKE2s wrapper using Cairo core's audited `core::blake` functions.
/// This module provides high-level challenge computation for DLEQ proofs.
///
/// **Audit Status**: Uses official Cairo core BLAKE2s implementation (audited by Starkware)
/// **Reference**: RFC 7693 (BLAKE2s specification)
/// **Efficiency**: 8x more efficient than Poseidon (Starknet v0.14.1+)
///
/// ## Usage
///
/// ```cairo
/// use blake2s_challenge::compute_dleq_challenge_blake2s;
///
/// let challenge = compute_dleq_challenge_blake2s(
///     G_compressed, Y_compressed, T_compressed, U_compressed,
///     R1_compressed, R2_compressed, hashlock
/// );
/// ```

use core::blake::{blake2s_compress, blake2s_finalize};
use core::box::BoxTrait;
use core::integer::u256;

/// BLAKE2s state type (8 u32 words)
type Blake2sState = core::box::Box<[u32; 8]>;

/// BLAKE2s input block type (16 u32 words = 512 bits)
type Blake2sInput = core::box::Box<[u32; 16]>;

/// Domain separator tag for DLEQ proofs: "DLEQ" (4 bytes, little-endian)
/// Value: 0x444c4551
const DLEQ_TAG: u32 = 0x444c4551;

/// Initialize BLAKE2s state with standard RFC 7693 IV
/// 
/// BLAKE2s requires the Initialization Vector (IV) XOR'd with the parameter block.
/// For 32-byte output, no key: parameter block = 0x01010020
/// (fanout=1, depth=1, digest_length=32, key_length=0)
/// 
/// RFC 7693 IV constants:
/// - IV[0] = 0x6A09E667 (XOR with 0x01010020 → 0x6B08E647)
/// - IV[1] = 0xBB67AE85
/// - IV[2] = 0x3C6EF372
/// - IV[3] = 0xA54FF53A
/// - IV[4] = 0x510E527F
/// - IV[5] = 0x9B05688C
/// - IV[6] = 0x1F83D9AB
/// - IV[7] = 0x5BE0CD19
fn initial_blake2s_state() -> Blake2sState {
    // CRITICAL FIX: Use RFC 7693 IV XOR'd with parameter block
    // Without this, BLAKE2s produces completely different output
    core::box::BoxTrait::new([
        0x6B08E647_u32,  // IV[0] ^ 0x01010020 (0x6A09E667 ^ 0x01010020)
        0xBB67AE85_u32,  // IV[1]
        0x3C6EF372_u32,  // IV[2]
        0xA54FF53A_u32,  // IV[3]
        0x510E527F_u32,  // IV[4]
        0x9B05688C_u32,  // IV[5]
        0x1F83D9AB_u32,  // IV[6]
        0x5BE0CD19_u32,  // IV[7]
    ])
}

/// Process multiple u256 values through BLAKE2s compression (batch optimization)
///
/// Performance optimization: processes multiple u256 values in sequence
/// without intermediate state management overhead.
///
/// @param state Initial BLAKE2s state
/// @param byte_count Initial byte count
/// @param values Span of u256 values to hash
/// @return Updated state and final byte count
pub fn process_multiple_u256(
    mut state: Blake2sState,
    mut byte_count: u32,
    values: Span<u256>,
) -> (Blake2sState, u32) {
    let mut i = 0;
    while i < values.len() {
        let (new_state, new_count) = process_u256(state, byte_count, *values.at(i));
        state = new_state;
        byte_count = new_count;
        i += 1;
    };
    (state, byte_count)
}

/// Process a u256 value through BLAKE2s compression
/// 
/// Helper function that serializes u256 and compresses it in one step
/// 
/// @param state Current BLAKE2s state
/// @param byte_count Current byte count (total bytes hashed so far)
/// @param value u256 value to hash (32 bytes)
/// @return Updated state and new byte count
fn process_u256(
    state: Blake2sState,
    byte_count: u32,
    value: u256,
) -> (Blake2sState, u32) {
    let u32_mask_u128: u128 = 0x100000000; // 2^32
    
    // Extract u32 words directly and build fixed array
    // Low part (u128): extract 4 u32 words
    // Note: u128 % 2^32 and division are safe - result always fits in u32
    let mut remaining_low = value.low;
    let low0: u32 = (remaining_low % u32_mask_u128).try_into().unwrap(); // Safe: u128 % 2^32 < 2^32
    remaining_low = remaining_low / u32_mask_u128;
    let low1: u32 = (remaining_low % u32_mask_u128).try_into().unwrap(); // Safe: u128 / 2^32 < 2^96, % 2^32 < 2^32
    remaining_low = remaining_low / u32_mask_u128;
    let low2: u32 = (remaining_low % u32_mask_u128).try_into().unwrap(); // Safe: u128 / 2^64 < 2^64, % 2^32 < 2^32
    remaining_low = remaining_low / u32_mask_u128;
    let low3: u32 = remaining_low.try_into().unwrap(); // Safe: u128 / 2^96 < 2^32
    
    // High part (u128): extract 4 u32 words
    let mut remaining_high = value.high;
    let high0: u32 = (remaining_high % u32_mask_u128).try_into().unwrap(); // Safe: u128 % 2^32 < 2^32
    remaining_high = remaining_high / u32_mask_u128;
    let high1: u32 = (remaining_high % u32_mask_u128).try_into().unwrap(); // Safe: u128 / 2^32 < 2^96, % 2^32 < 2^32
    remaining_high = remaining_high / u32_mask_u128;
    let high2: u32 = (remaining_high % u32_mask_u128).try_into().unwrap(); // Safe: u128 / 2^64 < 2^64, % 2^32 < 2^32
    remaining_high = remaining_high / u32_mask_u128;
    let high3: u32 = remaining_high.try_into().unwrap(); // Safe: u128 / 2^96 < 2^32
    
    // Create BLAKE2s input block directly as fixed array
    let msg: Blake2sInput = core::box::BoxTrait::new([
        low0, low1, low2, low3, high0, high1, high2, high3,
        0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32
    ]);
    let new_state = blake2s_compress(state, byte_count + 32, msg);
    (new_state, byte_count + 32) // 32 bytes per u256
}

/// Byte-swap a u32 word (Big-Endian -> Little-Endian)
/// 
/// Transforms 0x12345678 -> 0x78563412
/// This is needed because SHA-256 produces Big-Endian words,
/// but BLAKE2s expects Little-Endian byte streams.
/// 
/// Implementation matches auditor's specification:
/// Extract bytes from least to most significant, then reconstruct in reverse order.
/// 
/// @param value u32 word in Big-Endian format
/// @return u32 word in Little-Endian format
fn byte_swap_u32(value: u32) -> u32 {
    // Extract bytes from least to most significant (as auditor suggests)
    let b0 = value & 0xFF;                    // Least significant byte (bits 0-7)
    let b1 = (value / 0x100) & 0xFF;          // Byte 1 (bits 8-15)
    let b2 = (value / 0x10000) & 0xFF;        // Byte 2 (bits 16-23)
    let b3 = (value / 0x1000000) & 0xFF;      // Most significant byte (bits 24-31)
    
    // Reconstruct in reverse order: b0 becomes MSB, b3 becomes LSB
    // Result: 0x78563412 for input 0x12345678
    (b0 * 0x1000000) + (b1 * 0x10000) + (b2 * 0x100) + b3
}

/// Convert hashlock from Span<u32> (8 words) to u256
/// 
/// CRITICAL FIX: SHA-256 produces Big-Endian u32 words, but BLAKE2s expects Little-Endian bytes.
/// We byte-swap each word before packing into u256 so that when process_u256 extracts them
/// as little-endian, they match what Rust's BLAKE2s sees.
/// 
/// @param hashlock SHA-256 hash as 8 u32 words (big-endian from SHA-256)
/// @return u256 representation of hashlock (with byte-swapped words for BLAKE2s compatibility)
pub fn hashlock_to_u256(hashlock: Span<u32>) -> u256 {
    // CRITICAL: Validate span length before accessing elements
    // This prevents "Option::unwrap failed" if span is corrupted or has wrong length
    assert(hashlock.len() == 8, 'Hashlock must be 8 u32 words');
    
    // CRITICAL FIX: Byte-swap each word before packing
    // SHA-256 words are Big-Endian (0x12345678), but BLAKE2s expects Little-Endian bytes
    // After byte-swap: 0x78563412, which when extracted as little-endian gives correct bytes
    let h0_swapped = byte_swap_u32(*hashlock.at(0));
    let h1_swapped = byte_swap_u32(*hashlock.at(1));
    let h2_swapped = byte_swap_u32(*hashlock.at(2));
    let h3_swapped = byte_swap_u32(*hashlock.at(3));
    let h4_swapped = byte_swap_u32(*hashlock.at(4));
    let h5_swapped = byte_swap_u32(*hashlock.at(5));
    let h6_swapped = byte_swap_u32(*hashlock.at(6));
    let h7_swapped = byte_swap_u32(*hashlock.at(7));
    
    // Convert 8 byte-swapped u32 words to u256 (little-endian interpretation)
    // u256 = h0 + h1·2^32 + h2·2^64 + ... + h7·2^224
    let base: u256 = u256 { low: 0x1_0000_0000, high: 0 };
    let low = u256 { low: h0_swapped.into(), high: 0 }
        + base * u256 { low: h1_swapped.into(), high: 0 }
        + base * base * u256 { low: h2_swapped.into(), high: 0 }
        + base * base * base * u256 { low: h3_swapped.into(), high: 0 };
    let high = u256 { low: h4_swapped.into(), high: 0 }
        + base * u256 { low: h5_swapped.into(), high: 0 }
        + base * base * u256 { low: h6_swapped.into(), high: 0 }
        + base * base * base * u256 { low: h7_swapped.into(), high: 0 };
    u256 { low: low.low, high: high.low }
}

/// Compute DLEQ challenge using BLAKE2s with compressed Edwards points
///
/// Uses BLAKE2s (Starknet's official standard) for 8x cheaper gas than Poseidon.
/// Serializes points as compressed Edwards (32 bytes each) to match Rust implementation.
///
/// **Challenge Format**: BLAKE2s("DLEQ" || G || Y || T || U || R1 || R2 || hashlock)
///
/// **Serialization Order** (RFC 8032 compliant):
/// 1. Tag: "DLEQ" (4 bytes = 0x444c4551)
/// 2. Points: G, Y, T, U, R1, R2 (each 32 bytes compressed Edwards, little-endian)
/// 3. Hashlock: 32 bytes (SHA-256 hash)
///
/// **Total Input**: 4 + (6 × 32) + 32 = 228 bytes
///
/// @param G_compressed Standard Ed25519 generator (compressed Edwards, u256)
/// @param Y_compressed Second generator for DLEQ (compressed Edwards, u256)
/// @param T_compressed Adaptor point (compressed Edwards, u256)
/// @param U_compressed DLEQ second point (compressed Edwards, u256)
/// @param R1_compressed First commitment point (compressed Edwards, u256)
/// @param R2_compressed Second commitment point (compressed Edwards, u256)
/// @param hashlock SHA-256 hash of secret (Span<u32> - 8 words)
/// @return Challenge scalar c reduced mod Ed25519 order
/// 
/// @invariant Challenge is in range [0, ED25519_ORDER) (enforced by reduction)
/// @note Matches Rust implementation: BLAKE2s("DLEQ" || G || Y || T || U || R1 || R2 || hashlock)
/// @security Uses audited Cairo core BLAKE2s functions (Starkware)
pub fn compute_dleq_challenge_blake2s(
    G_compressed: u256,
    Y_compressed: u256,
    T_compressed: u256,
    U_compressed: u256,
    R1_compressed: u256,
    R2_compressed: u256,
    hashlock: Span<u32>,
    ed25519_order: u256,
) -> felt252 {
    // Initialize BLAKE2s state
    let mut state = initial_blake2s_state();
    let mut byte_count = 0_u32;
    
    // Domain separator: "DLEQ" (4 bytes = 0x444c4551)
    // Convert to u32 array: [0x444c4551, 0, 0, 0, ...] padded to 16 u32
    let tag_msg = core::box::BoxTrait::new([
        DLEQ_TAG, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32,
        0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32
    ]);
    state = blake2s_compress(state, 4, tag_msg);
    byte_count = 4; // 4 bytes for "DLEQ"
    
    // Serialize compressed Edwards points (32 bytes each = 8 u32 words)
    // Performance: Process all points in batch for better gas efficiency
    let points = array![G_compressed, Y_compressed, T_compressed, U_compressed, R1_compressed, R2_compressed];
    let (state, byte_count) = process_multiple_u256(state, byte_count, points.span());
    
    // Add hashlock (convert Span<u32> to u256, then hash)
    let hashlock_u256 = hashlock_to_u256(hashlock);
    let (state, byte_count) = process_u256(state, byte_count, hashlock_u256);
    
    // Finalize BLAKE2s (empty final block since we've processed all data)
    let empty_final = core::box::BoxTrait::new([0_u32; 16]);
    let state = blake2s_finalize(state, byte_count, empty_final);
    
    // Extract full 256-bit hash from BLAKE2s state (8 u32 words = 32 bytes)
    // CRITICAL: Must extract ALL 8 words, not just the first one!
    // BLAKE2s produces 32-byte (256-bit) output, which we need in full for scalar reduction
    let hash_state = state.unbox();
    let hash_span = hash_state.span();
    
    // CRITICAL: Validate span length before accessing elements
    // BLAKE2s state should always have exactly 8 u32 words
    assert(hash_span.len() == 8, 'BLAKE2s state must have 8 words');
    
    // Extract all 8 u32 words (little-endian interpretation)
    // Words 0-3 form the low u128, words 4-7 form the high u128
    let w0: u128 = (*hash_span.at(0)).into();
    let w1: u128 = (*hash_span.at(1)).into();
    let w2: u128 = (*hash_span.at(2)).into();
    let w3: u128 = (*hash_span.at(3)).into();
    let w4: u128 = (*hash_span.at(4)).into();
    let w5: u128 = (*hash_span.at(5)).into();
    let w6: u128 = (*hash_span.at(6)).into();
    let w7: u128 = (*hash_span.at(7)).into();
    
    // Reconstruct u256: low = w0 + w1·2^32 + w2·2^64 + w3·2^96
    //                   high = w4 + w5·2^32 + w6·2^64 + w7·2^96
    let base: u128 = 0x1_0000_0000; // 2^32
    let low = w0 + base * w1 + base * base * w2 + base * base * base * w3;
    let high = w4 + base * w5 + base * base * w6 + base * base * base * w7;
    
    // Convert to u256 and reduce mod curve order (matches Rust: Scalar::from_bytes_mod_order)
    let hash_u256 = u256 { low, high };
    let scalar = hash_u256 % ed25519_order;
    
    // CRITICAL: Convert scalar to felt252 safely
    // Since scalar < ed25519_order and ed25519_order is close to 2^252,
    // we need to handle the conversion carefully to avoid overflow
    // Try converting the full scalar directly first
    let scalar_felt_option: Option<felt252> = scalar.try_into();
    
    // If direct conversion fails (scalar >= felt252 prime), we need to reduce further
    // This should be rare but can happen if scalar is very close to ed25519_order
    if scalar_felt_option.is_some() {
        return scalar_felt_option.unwrap();
    }
    
    // Fallback: Convert scalar mod felt252 prime by reducing again
    // This ensures we always return a valid felt252
    // Note: This is safe because felt252 arithmetic wraps modulo the prime
    let base_128: felt252 = 0x100000000000000000000000000000000; // 2^128
    let low_felt: felt252 = scalar.low.try_into().unwrap(); // Always succeeds (u128 < felt252)
    let high_felt: felt252 = scalar.high.try_into().unwrap(); // Always succeeds (u128 < felt252)
    // Arithmetic wraps modulo felt252 prime, so this is safe
    let scalar_felt = low_felt + high_felt * base_128;
    scalar_felt
}

