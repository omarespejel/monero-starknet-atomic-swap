/// # BLAKE2s Challenge Computation Module
///
/// Production-grade BLAKE2s wrapper using Cairo core's production-grade `core::blake` functions.
/// This module provides high-level challenge computation for DLEQ proofs.
///
/// **Status**: Uses official Cairo core BLAKE2s implementation (production-grade)
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

/// Domain separator tag for DLEQ proofs: "DLEQ" (4 bytes)
/// 
/// CRITICAL: BLAKE2s reads u32 as little-endian bytes, so we must store
/// the tag in little-endian format: byte0='D', byte1='L', byte2='E', byte3='Q'
/// As u32: 0x44 + (0x4C << 8) + (0x45 << 16) + (0x51 << 24) = 0x51454c44
/// 
/// Previous value (0x444c4551) was wrong - it produced "QELD" when read as bytes
const DLEQ_TAG: u32 = 0x51454c44_u32;

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

// Note: We extract u32 words directly inline in compute_dleq_challenge_blake2s
// to avoid array indexing issues in Cairo

/// Byte-swap a u32 word (Big-Endian -> Little-Endian)
/// 
/// Transforms 0x12345678 -> 0x78563412
/// This is needed because SHA-256 produces Big-Endian words,
/// but BLAKE2s expects Little-Endian byte streams.
/// 
/// Implementation matches specification:
/// Extract bytes from least to most significant, then reconstruct in reverse order.
/// 
/// @param value u32 word in Big-Endian format
/// @return u32 word in Little-Endian format
fn byte_swap_u32(value: u32) -> u32 {
    // Extract bytes from least to most significant
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
/// 1. Tag: "DLEQ" (4 bytes)
/// 2. Points: G, Y, T, U, R1, R2 (each 32 bytes compressed Edwards, little-endian)
/// 3. Hashlock: 32 bytes (SHA-256 hash)
///
/// **Total Input**: 4 + (6 × 32) + 32 = 228 bytes
///
/// **CRITICAL FIX**: Accumulate all bytes into a continuous buffer before compressing.
/// Rust's BLAKE2s accumulates bytes and only compresses when it has a full 64-byte block.
/// Previous implementation compressed each item separately, causing block misalignment.
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
/// @security Uses production-grade Cairo core BLAKE2s functions (Starkware)
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
    // CRITICAL FIX: Build continuous byte buffer first (matches Rust's accumulation)
    // Total: 228 bytes = 57 u32 words
    // Process in 4 blocks of 16 u32 words (64 bytes) each
    
    // Helper to extract u32 words from u256
    let u32_mask_u128: u128 = 0x100000000; // 2^32
    
    // Extract G words
    let mut g_low = G_compressed.low;
    let g0: u32 = (g_low % u32_mask_u128).try_into().unwrap();
    g_low = g_low / u32_mask_u128;
    let g1: u32 = (g_low % u32_mask_u128).try_into().unwrap();
    g_low = g_low / u32_mask_u128;
    let g2: u32 = (g_low % u32_mask_u128).try_into().unwrap();
    g_low = g_low / u32_mask_u128;
    let g3: u32 = g_low.try_into().unwrap();
    let mut g_high = G_compressed.high;
    let g4: u32 = (g_high % u32_mask_u128).try_into().unwrap();
    g_high = g_high / u32_mask_u128;
    let g5: u32 = (g_high % u32_mask_u128).try_into().unwrap();
    g_high = g_high / u32_mask_u128;
    let g6: u32 = (g_high % u32_mask_u128).try_into().unwrap();
    g_high = g_high / u32_mask_u128;
    let g7: u32 = g_high.try_into().unwrap();
    
    // Extract Y words
    let mut y_low = Y_compressed.low;
    let y0: u32 = (y_low % u32_mask_u128).try_into().unwrap();
    y_low = y_low / u32_mask_u128;
    let y1: u32 = (y_low % u32_mask_u128).try_into().unwrap();
    y_low = y_low / u32_mask_u128;
    let y2: u32 = (y_low % u32_mask_u128).try_into().unwrap();
    y_low = y_low / u32_mask_u128;
    let y3: u32 = y_low.try_into().unwrap();
    let mut y_high = Y_compressed.high;
    let y4: u32 = (y_high % u32_mask_u128).try_into().unwrap();
    y_high = y_high / u32_mask_u128;
    let y5: u32 = (y_high % u32_mask_u128).try_into().unwrap();
    y_high = y_high / u32_mask_u128;
    let y6: u32 = (y_high % u32_mask_u128).try_into().unwrap();
    y_high = y_high / u32_mask_u128;
    let y7: u32 = y_high.try_into().unwrap();
    
    // Extract T words
    let mut t_low = T_compressed.low;
    let t0: u32 = (t_low % u32_mask_u128).try_into().unwrap();
    t_low = t_low / u32_mask_u128;
    let t1: u32 = (t_low % u32_mask_u128).try_into().unwrap();
    t_low = t_low / u32_mask_u128;
    let t2: u32 = (t_low % u32_mask_u128).try_into().unwrap();
    t_low = t_low / u32_mask_u128;
    let t3: u32 = t_low.try_into().unwrap();
    let mut t_high = T_compressed.high;
    let t4: u32 = (t_high % u32_mask_u128).try_into().unwrap();
    t_high = t_high / u32_mask_u128;
    let t5: u32 = (t_high % u32_mask_u128).try_into().unwrap();
    t_high = t_high / u32_mask_u128;
    let t6: u32 = (t_high % u32_mask_u128).try_into().unwrap();
    t_high = t_high / u32_mask_u128;
    let t7: u32 = t_high.try_into().unwrap();
    
    // Extract U words
    let mut u_low = U_compressed.low;
    let u0: u32 = (u_low % u32_mask_u128).try_into().unwrap();
    u_low = u_low / u32_mask_u128;
    let u1: u32 = (u_low % u32_mask_u128).try_into().unwrap();
    u_low = u_low / u32_mask_u128;
    let u2: u32 = (u_low % u32_mask_u128).try_into().unwrap();
    u_low = u_low / u32_mask_u128;
    let u3: u32 = u_low.try_into().unwrap();
    let mut u_high = U_compressed.high;
    let u4: u32 = (u_high % u32_mask_u128).try_into().unwrap();
    u_high = u_high / u32_mask_u128;
    let u5: u32 = (u_high % u32_mask_u128).try_into().unwrap();
    u_high = u_high / u32_mask_u128;
    let u6: u32 = (u_high % u32_mask_u128).try_into().unwrap();
    u_high = u_high / u32_mask_u128;
    let u7: u32 = u_high.try_into().unwrap();
    
    // Extract R1 words
    let mut r1_low = R1_compressed.low;
    let r1_0: u32 = (r1_low % u32_mask_u128).try_into().unwrap();
    r1_low = r1_low / u32_mask_u128;
    let r1_1: u32 = (r1_low % u32_mask_u128).try_into().unwrap();
    r1_low = r1_low / u32_mask_u128;
    let r1_2: u32 = (r1_low % u32_mask_u128).try_into().unwrap();
    r1_low = r1_low / u32_mask_u128;
    let r1_3: u32 = r1_low.try_into().unwrap();
    let mut r1_high = R1_compressed.high;
    let r1_4: u32 = (r1_high % u32_mask_u128).try_into().unwrap();
    r1_high = r1_high / u32_mask_u128;
    let r1_5: u32 = (r1_high % u32_mask_u128).try_into().unwrap();
    r1_high = r1_high / u32_mask_u128;
    let r1_6: u32 = (r1_high % u32_mask_u128).try_into().unwrap();
    r1_high = r1_high / u32_mask_u128;
    let r1_7: u32 = r1_high.try_into().unwrap();
    
    // Extract R2 words
    let mut r2_low = R2_compressed.low;
    let r2_0: u32 = (r2_low % u32_mask_u128).try_into().unwrap();
    r2_low = r2_low / u32_mask_u128;
    let r2_1: u32 = (r2_low % u32_mask_u128).try_into().unwrap();
    r2_low = r2_low / u32_mask_u128;
    let r2_2: u32 = (r2_low % u32_mask_u128).try_into().unwrap();
    r2_low = r2_low / u32_mask_u128;
    let r2_3: u32 = r2_low.try_into().unwrap();
    let mut r2_high = R2_compressed.high;
    let r2_4: u32 = (r2_high % u32_mask_u128).try_into().unwrap();
    r2_high = r2_high / u32_mask_u128;
    let r2_5: u32 = (r2_high % u32_mask_u128).try_into().unwrap();
    r2_high = r2_high / u32_mask_u128;
    let r2_6: u32 = (r2_high % u32_mask_u128).try_into().unwrap();
    r2_high = r2_high / u32_mask_u128;
    let r2_7: u32 = r2_high.try_into().unwrap();
    
    // Convert hashlock to u256 and extract words
    let hashlock_u256 = hashlock_to_u256(hashlock);
    let mut h_low = hashlock_u256.low;
    let h0: u32 = (h_low % u32_mask_u128).try_into().unwrap();
    h_low = h_low / u32_mask_u128;
    let h1: u32 = (h_low % u32_mask_u128).try_into().unwrap();
    h_low = h_low / u32_mask_u128;
    let h2: u32 = (h_low % u32_mask_u128).try_into().unwrap();
    h_low = h_low / u32_mask_u128;
    let h3: u32 = h_low.try_into().unwrap();
    let mut h_high = hashlock_u256.high;
    let h4: u32 = (h_high % u32_mask_u128).try_into().unwrap();
    h_high = h_high / u32_mask_u128;
    let h5: u32 = (h_high % u32_mask_u128).try_into().unwrap();
    h_high = h_high / u32_mask_u128;
    let h6: u32 = (h_high % u32_mask_u128).try_into().unwrap();
    h_high = h_high / u32_mask_u128;
    let h7: u32 = h_high.try_into().unwrap();
    
    // Build message buffer directly: [DLEQ_TAG(1) + points(6*8) + hashlock(8) + padding(7)] = 64 words
    // Block 0: words 0-15 (bytes 0-63) - contains DLEQ_TAG + G + Y[0-6]
    let block0 = core::box::BoxTrait::new([
        DLEQ_TAG, g0, g1, g2, g3, g4, g5, g6,
        g7, y0, y1, y2, y3, y4, y5, y6
    ]);
    
    // Block 1: words 16-31 (bytes 64-127) - contains Y[7] + T + U[0-6]
    let block1 = core::box::BoxTrait::new([
        y7, t0, t1, t2, t3, t4, t5, t6,
        t7, u0, u1, u2, u3, u4, u5, u6
    ]);
    
    // Block 2: words 32-47 (bytes 128-191) - contains U[7] + R1 + R2[0-6]
    let block2 = core::box::BoxTrait::new([
        u7, r1_0, r1_1, r1_2, r1_3, r1_4, r1_5, r1_6,
        r1_7, r2_0, r2_1, r2_2, r2_3, r2_4, r2_5, r2_6
    ]);
    
    // Block 3: words 48-63 (bytes 192-255) - contains R2[7] + hashlock + padding
    // This is the final block with remaining 36 bytes (words 48-56) + padding
    let block3 = core::box::BoxTrait::new([
        r2_7, h0, h1, h2, h3, h4, h5, h6,
        h7, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32, 0_u32
    ]);
    
    // Initialize BLAKE2s state
    let mut state = initial_blake2s_state();
    let total_bytes = 228_u32; // 4 + 6*32 + 32
    
    // Process blocks sequentially (matches Rust's accumulation)
    state = blake2s_compress(state, 64, block0);
    state = blake2s_compress(state, 128, block1);
    state = blake2s_compress(state, 192, block2);
    state = blake2s_finalize(state, total_bytes, block3);
    
    // Extract full 256-bit hash from BLAKE2s state (8 u32 words = 32 bytes)
    let hash_state = state.unbox();
    let hash_span = hash_state.span();
    
    // CRITICAL: Validate span length before accessing elements
    assert(hash_span.len() == 8, 'BLAKE2s state must have 8 words');
    
    // DEBUG: Extract state words for comparison with Rust
    // These will be used in debug assertions to print values
    let h0 = *hash_span.at(0);
    let h1 = *hash_span.at(1);
    let h2 = *hash_span.at(2);
    let h3 = *hash_span.at(3);
    let h4 = *hash_span.at(4);
    let h5 = *hash_span.at(5);
    let h6 = *hash_span.at(6);
    let h7 = *hash_span.at(7);
    
    // Extract all 8 u32 words in original order (no reversal, no byte-swap)
    // Rust's Scalar::from_bytes_mod_order treats 32 bytes as little-endian u256:
    // - h[0] contains bytes[0..4] (little-endian u32)
    // - h[1] contains bytes[4..8] (little-endian u32)
    // - ...
    // - h[7] contains bytes[28..32] (little-endian u32)
    // So: low = h[0] + h[1]*2^32 + h[2]*2^64 + h[3]*2^96
    //     high = h[4] + h[5]*2^32 + h[6]*2^64 + h[7]*2^96
    let w0: u128 = h0.into();
    let w1: u128 = h1.into();
    let w2: u128 = h2.into();
    let w3: u128 = h3.into();
    let w4: u128 = h4.into();
    let w5: u128 = h5.into();
    let w6: u128 = h6.into();
    let w7: u128 = h7.into();
    
    // Reconstruct u256: low = w0 + w1·2^32 + w2·2^64 + w3·2^96
    //                   high = w4 + w5·2^32 + w6·2^64 + w7·2^96
    let base: u128 = 0x1_0000_0000; // 2^32
    let low = w0 + base * w1 + base * base * w2 + base * base * base * w3;
    let high = w4 + base * w5 + base * base * w6 + base * base * base * w7;
    
    // Convert to u256 and reduce mod curve order (matches Rust: Scalar::from_bytes_mod_order)
    // CRITICAL: Rust stores the REDUCED scalar in test_vectors.json, not the full digest
    // So we must reduce here to match Rust's format
    let hash_u256 = u256 { low, high };
    let scalar = hash_u256 % ed25519_order;
    
    // Convert reduced scalar to felt252 (for challenge comparison)
    // This matches Rust's Scalar::to_bytes() format (little-endian bytes)
    let base_128: felt252 = 0x100000000000000000000000000000000; // 2^128
    let low_felt: felt252 = scalar.low.try_into().unwrap();
    let high_felt: felt252 = scalar.high.try_into().unwrap();
    let scalar_felt = low_felt + high_felt * base_128;
    scalar_felt
}

