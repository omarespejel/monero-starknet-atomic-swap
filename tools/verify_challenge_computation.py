#!/usr/bin/env python3
"""
Verify DLEQ challenge computation byte-by-byte.

This script computes the challenge exactly as Cairo should, allowing us to
compare byte-by-byte with Rust's computation to find serialization differences.
"""

import json
import sys
from pathlib import Path

import hashlib


def swap_u32(x: int) -> int:
    """Byte-swap a u32 (big-endian -> little-endian)."""
    return ((x & 0xFF) << 24) | ((x & 0xFF00) << 8) | \
           ((x & 0xFF0000) >> 8) | ((x >> 24) & 0xFF)


def compute_dleq_challenge_python():
    """Compute challenge exactly as Cairo should."""
    
    # Load test vectors
    vectors_path = Path(__file__).parent.parent / "rust" / "test_vectors.json"
    if not vectors_path.exists():
        print(f"ERROR: {vectors_path} not found")
        sys.exit(1)
    
    with open(vectors_path) as f:
        vectors = json.load(f)
    
    print("=" * 80)
    print("DLEQ CHALLENGE COMPUTATION VERIFICATION")
    print("=" * 80)
    print()
    
    # Constants from test_vectors.json (compressed Edwards points, 32 bytes each)
    # These are stored as hex strings, need to convert to bytes
    G_hex = vectors["g_compressed"]
    Y_hex = vectors["y_compressed"]
    T_hex = vectors["adaptor_point_compressed"]
    U_hex = vectors["second_point_compressed"]
    R1_hex = vectors["r1_compressed"]
    R2_hex = vectors["r2_compressed"]
    
    # Convert hex strings to bytes (little-endian u256 representation)
    # Each compressed point is 32 bytes (256 bits)
    G = bytes.fromhex(G_hex)
    Y = bytes.fromhex(Y_hex)
    T = bytes.fromhex(T_hex)
    U = bytes.fromhex(U_hex)
    R1 = bytes.fromhex(R1_hex)
    R2 = bytes.fromhex(R2_hex)
    
    print("### INPUT POINTS (compressed Edwards, 32 bytes each) ###")
    print(f"G:  {G_hex}")
    print(f"Y:  {Y_hex}")
    print(f"T:  {T_hex}")
    print(f"U:  {U_hex}")
    print(f"R1: {R1_hex}")
    print(f"R2: {R2_hex}")
    print()
    
    # Hashlock (8 x u32, big-endian from SHA-256)
    # CRITICAL: Rust feeds hashlock directly as bytes [u8; 32]
    # Cairo stores as BE u32 words, byte-swaps them, then extracts as u32 values
    # When these u32 values are put into BLAKE2s blocks, BLAKE2s reads them as LE bytes
    # So: BE word -> swap -> u32 value -> BLAKE2s reads as LE bytes
    # This means: swap word -> bytes should match Rust's direct bytes
    hashlock_hex = vectors["hashlock"]
    hashlock_be = [
        int(hashlock_hex[i:i+8], 16) for i in range(0, len(hashlock_hex), 8)
    ]
    
    print("### HASHLOCK (8 x u32, big-endian from SHA-256) ###")
    print(f"Hashlock hex: {hashlock_hex}")
    print(f"Hashlock BE words: {[hex(w) for w in hashlock_be]}")
    
    # Rust feeds hashlock directly as bytes (no byte-swap needed)
    # Cairo byte-swaps each word, then extracts as u32, which BLAKE2s reads as LE bytes
    # So we should use Rust's direct bytes (what Rust actually feeds to BLAKE2s)
    hashlock_bytes = bytes.fromhex(hashlock_hex)
    
    print(f"Hashlock bytes (Rust feeds directly): {hashlock_bytes.hex()}")
    print()
    
    # DLEQ tag
    # Rust: b"DLEQ" = [0x44, 0x4C, 0x45, 0x51] (ASCII bytes)
    # Cairo: DLEQ_TAG = 0x51454c44 (little-endian u32)
    # When Cairo puts 0x51454c44 as u32 into BLAKE2s, BLAKE2s reads it as LE bytes:
    # [0x44, 0x4C, 0x45, 0x51] which is "DLEQ" ✓
    tag = b'DLEQ'  # Rust uses this directly
    tag_bytes = tag  # Rust feeds "DLEQ" as 4 bytes directly
    
    print("### DLEQ TAG ###")
    print(f"Tag (Rust): {tag_bytes}")
    print(f"Tag (hex): {tag_bytes.hex()}")
    print(f"Cairo uses: 0x51454c44 (u32 LE, reads as bytes: {bytes.fromhex('444c4551').hex()})")
    print()
    
    # Build input: tag || G || Y || T || U || R1 || R2 || hashlock
    # Match Rust exactly: Rust feeds everything as bytes directly
    data = tag_bytes + G + Y + T + U + R1 + R2 + hashlock_bytes
    
    print("### BLAKE2s INPUT ###")
    print(f"Total input length: {len(data)} bytes")
    print(f"Input hex (first 64 bytes): {data[:64].hex()}")
    print(f"Input hex (last 64 bytes): {data[-64:].hex()}")
    print()
    
    # BLAKE2s-256 (using Python's hashlib)
    h = hashlib.blake2s(data, digest_size=32)
    digest = h.digest()
    
    print("### BLAKE2s OUTPUT ###")
    print(f"BLAKE2s digest: {digest.hex()}")
    print()
    
    # Convert to u256 (little-endian)
    low = int.from_bytes(digest[:16], 'little')
    high = int.from_bytes(digest[16:], 'little')
    
    print("### CHALLENGE (u256) ###")
    print(f"Challenge u256: low=0x{low:032x}, high=0x{high:032x}")
    
    # Full challenge as integer
    full = low + (high << 128)
    print(f"Full challenge: 0x{full:064x}")
    print()
    
    # Reduce mod Ed25519 order
    ED25519_ORDER = 0x1000000000000000000000000000000014def9dea2f79cd65812631a5cf5d3ed
    reduced = full % ED25519_ORDER
    
    print("### CHALLENGE (reduced mod Ed25519 order) ###")
    print(f"Reduced (mod n): 0x{reduced:064x}")
    
    # Truncated (low 128 bits)
    truncated = reduced & ((1 << 128) - 1)
    print(f"Truncated (low 128 bits): 0x{truncated:032x}")
    print()
    
    # Compare with expected from test_vectors.json
    expected_challenge_hex = vectors["challenge"]
    expected_challenge_int = int(expected_challenge_hex, 16)
    expected_truncated = expected_challenge_int & ((1 << 128) - 1)
    
    print("### COMPARISON WITH test_vectors.json ###")
    print(f"Expected (full):     0x{expected_challenge_int:064x}")
    print(f"Expected (truncated): 0x{expected_truncated:032x}")
    print()
    
    if reduced == expected_challenge_int:
        print("✅ FULL CHALLENGE MATCHES!")
    else:
        print("❌ FULL CHALLENGE MISMATCH!")
        print(f"   Computed: 0x{reduced:064x}")
        print(f"   Expected: 0x{expected_challenge_int:064x}")
    
    if truncated == expected_truncated:
        print("✅ TRUNCATED CHALLENGE MATCHES!")
    else:
        print("❌ TRUNCATED CHALLENGE MISMATCH!")
        print(f"   Computed: 0x{truncated:032x}")
        print(f"   Expected: 0x{expected_truncated:032x}")
    
    print()
    print("=" * 80)
    print("If mismatch, check:")
    print("  1. Point serialization (G, Y, T, U, R1, R2)")
    print("  2. Hashlock byte-swapping")
    print("  3. DLEQ tag byte order")
    print("  4. BLAKE2s input construction")
    print("=" * 80)


if __name__ == "__main__":
    compute_dleq_challenge_python()

