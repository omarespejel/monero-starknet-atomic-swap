#!/usr/bin/env python3
"""
Generate DLEQ proof for an arbitrary adaptor point.

This tool generates a complete DLEQ proof (challenge, response, commitments, hints)
for a given adaptor point and secret. This enables testing with various adaptor points
to discover vulnerabilities.

Usage:
    python generate_dleq_for_adaptor_point.py <secret_hex> [--output-format cairo|json]

Example:
    python generate_dleq_for_adaptor_point.py 099dd9b73e2e84db472b342dc3ab0520f654fd8a81d644180477730a90af8900
"""

import sys
import json
import hashlib
from typing import Tuple
import argparse

try:
    from garaga.hints.fake_glv import get_fake_glv_hint
    from garaga.definitions import G1Point, get_G, get_ED25519_order_modulus
    from garaga.ec_ops import msm_g1
    from garaga.signatures.eddsa_25519 import (
        decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point,
        compress_edwards_pt_to_y_compressed_le,
    )
except ImportError:
    print("Error: garaga library not found. Install with: pip install garaga")
    sys.exit(1)


def secret_to_scalar(secret_bytes: bytes) -> int:
    """Convert secret bytes to Ed25519 scalar (mod order)."""
    order = get_ED25519_order_modulus()
    scalar = int.from_bytes(secret_bytes, byteorder='little') % order
    return scalar


def hashlock_from_secret(secret_bytes: bytes) -> bytes:
    """Compute SHA-256 hashlock from secret."""
    return hashlib.sha256(secret_bytes).digest()


def hashlock_to_u32_array(hashlock: bytes) -> list[int]:
    """Convert hashlock bytes to u32 array (8 words, big-endian)."""
    assert len(hashlock) == 32
    words = []
    for i in range(0, 32, 4):
        word = int.from_bytes(hashlock[i:i+4], byteorder='big')
        words.append(word)
    return words


def generate_deterministic_nonce(secret_scalar: int, hashlock: bytes) -> int:
    """Generate deterministic nonce k using RFC6979-style approach."""
    order = get_ED25519_order_modulus()
    # k = SHA256(secret || hashlock || counter) mod order
    hasher = hashlib.sha256()
    hasher.update(secret_scalar.to_bytes(32, byteorder='little'))
    hasher.update(hashlock)
    hasher.update(b'\x00')  # Counter
    k_bytes = hasher.digest()
    k = int.from_bytes(k_bytes, byteorder='little') % order
    return k


def compute_blake2s_challenge(
    g_compressed: bytes,
    y_compressed: bytes,
    t_compressed: bytes,
    u_compressed: bytes,
    r1_compressed: bytes,
    r2_compressed: bytes,
    hashlock: bytes,
) -> int:
    """Compute BLAKE2s challenge (matches Cairo implementation)."""
    import hashlib
    # Use BLAKE2s (256-bit output)
    hasher = hashlib.blake2s(digest_size=32)
    
    # Tag: "DLEQ" (4 bytes)
    hasher.update(b"DLEQ")
    
    # Points in compressed format (32 bytes each)
    hasher.update(g_compressed)
    hasher.update(y_compressed)
    hasher.update(t_compressed)
    hasher.update(u_compressed)
    hasher.update(r1_compressed)
    hasher.update(r2_compressed)
    
    # Hashlock (32 bytes)
    hasher.update(hashlock)
    
    # Reduce mod curve order
    order = get_ED25519_order_modulus()
    challenge_bytes = hasher.digest()
    challenge = int.from_bytes(challenge_bytes, byteorder='little') % order
    return challenge


def generate_dleq_proof(
    secret_hex: str,
    adaptor_point_weierstrass: G1Point = None,
) -> dict:
    """
    Generate complete DLEQ proof for given secret.
    
    If adaptor_point_weierstrass is None, computes T = t·G from secret.
    Otherwise, uses provided adaptor point (must match secret).
    """
    # Parse secret
    secret_bytes = bytes.fromhex(secret_hex)
    if len(secret_bytes) != 32:
        raise ValueError(f"Secret must be 32 bytes (64 hex chars), got {len(secret_bytes)}")
    
    # Convert to scalar
    secret_scalar = secret_to_scalar(secret_bytes)
    
    # Compute hashlock
    hashlock = hashlock_from_secret(secret_bytes)
    hashlock_u32 = hashlock_to_u32_array(hashlock)
    
    # Get generators
    G = get_G(0)  # Ed25519 generator
    Y = msm_g1([G], [2], 0, None)  # Y = 2·G (second generator)
    
    # Compute adaptor point T = t·G
    if adaptor_point_weierstrass is None:
        # Generate hint for t·G
        t_hint = get_fake_glv_hint(secret_scalar, G, 0)
        T = msm_g1([G], [secret_scalar], 0, t_hint)
    else:
        T = adaptor_point_weierstrass
    
    # Compute U = t·Y
    t_y_hint = get_fake_glv_hint(secret_scalar, Y, 0)
    U = msm_g1([Y], [secret_scalar], 0, t_y_hint)
    
    # Generate deterministic nonce k
    k = generate_deterministic_nonce(secret_scalar, hashlock)
    
    # Compute commitments R1 = k·G, R2 = k·Y
    k_g_hint = get_fake_glv_hint(k, G, 0)
    R1 = msm_g1([G], [k], 0, k_g_hint)
    
    k_y_hint = get_fake_glv_hint(k, Y, 0)
    R2 = msm_g1([Y], [k], 0, k_y_hint)
    
    # Compress points for challenge computation
    g_compressed = compress_edwards_pt_to_y_compressed_le(G)
    y_compressed = compress_edwards_pt_to_y_compressed_le(Y)
    t_compressed = compress_edwards_pt_to_y_compressed_le(T)
    u_compressed = compress_edwards_pt_to_y_compressed_le(U)
    r1_compressed = compress_edwards_pt_to_y_compressed_le(R1)
    r2_compressed = compress_edwards_pt_to_y_compressed_le(R2)
    
    # Compute challenge c
    order = get_ED25519_order_modulus()
    challenge = compute_blake2s_challenge(
        g_compressed, y_compressed, t_compressed, u_compressed,
        r1_compressed, r2_compressed, hashlock
    )
    
    # Compute response s = k + c·t mod order
    response = (k + challenge * secret_scalar) % order
    
    # Generate MSM hints for DLEQ verification
    # s_hint_for_g: hint for s·G
    s_g_hint = get_fake_glv_hint(response, G, 0)
    
    # s_hint_for_y: hint for s·Y
    s_y_hint = get_fake_glv_hint(response, Y, 0)
    
    # c_neg_hint_for_t: hint for (-c)·T
    c_neg = (order - challenge) % order
    c_neg_t_hint = get_fake_glv_hint(c_neg, T, 0)
    
    # c_neg_hint_for_u: hint for (-c)·U
    c_neg_u_hint = get_fake_glv_hint(c_neg, U, 0)
    
    # Get sqrt hints (x-coordinates) for decompression
    # Note: This requires converting Weierstrass back to Edwards
    # For now, we'll use placeholder (0) - real implementation needs Edwards conversion
    t_sqrt_hint = b'\x00' * 32  # TODO: Extract x-coordinate from T
    u_sqrt_hint = b'\x00' * 32  # TODO: Extract x-coordinate from U
    r1_sqrt_hint = b'\x00' * 32  # TODO: Extract x-coordinate from R1
    r2_sqrt_hint = b'\x00' * 32  # TODO: Extract x-coordinate from R2
    
    # Convert to Cairo-compatible format
    def u256_from_bytes(b: bytes) -> dict:
        """Convert 32 bytes to u256 {low, high}."""
        low_bytes = b[:16]
        high_bytes = b[16:]
        low = int.from_bytes(low_bytes, byteorder='little')
        high = int.from_bytes(high_bytes, byteorder='little')
        return {"low": hex(low), "high": hex(high)}
    
    def hint_to_cairo_array(hint: list) -> list[str]:
        """Convert hint list to Cairo array format."""
        return [hex(x) for x in hint]
    
    return {
        "secret_hex": secret_hex,
        "hashlock_u32": hashlock_u32,
        "adaptor_point_compressed": u256_from_bytes(t_compressed),
        "adaptor_point_sqrt_hint": u256_from_bytes(t_sqrt_hint),
        "second_point_compressed": u256_from_bytes(u_compressed),
        "second_point_sqrt_hint": u256_from_bytes(u_sqrt_hint),
        "challenge": hex(challenge),
        "response": hex(response),
        "g_compressed": u256_from_bytes(g_compressed),
        "y_compressed": u256_from_bytes(y_compressed),
        "r1_compressed": u256_from_bytes(r1_compressed),
        "r1_sqrt_hint": u256_from_bytes(r1_sqrt_hint),
        "r2_compressed": u256_from_bytes(r2_compressed),
        "r2_sqrt_hint": u256_from_bytes(r2_sqrt_hint),
        "s_hint_for_g": hint_to_cairo_array(s_g_hint),
        "s_hint_for_y": hint_to_cairo_array(s_y_hint),
        "c_neg_hint_for_t": hint_to_cairo_array(c_neg_t_hint),
        "c_neg_hint_for_u": hint_to_cairo_array(c_neg_u_hint),
    }


def main():
    parser = argparse.ArgumentParser(description="Generate DLEQ proof for adaptor point")
    parser.add_argument("secret_hex", help="Secret in hex format (64 chars)")
    parser.add_argument("--output-format", choices=["json", "cairo"], default="json",
                       help="Output format (default: json)")
    parser.add_argument("--output-file", help="Output file path (default: stdout)")
    
    args = parser.parse_args()
    
    try:
        proof = generate_dleq_proof(args.secret_hex)
        
        if args.output_format == "json":
            output = json.dumps(proof, indent=2)
        else:  # cairo
            # Generate Cairo constants
            output = f"""// DLEQ proof for secret: {args.secret_hex}
// Generated by tools/generate_dleq_for_adaptor_point.py

const DLEQ_HASHLOCK: [u32; 8] = {proof['hashlock_u32']};

const DLEQ_ADAPTOR_POINT_COMPRESSED: u256 = u256 {{
    low: {proof['adaptor_point_compressed']['low']},
    high: {proof['adaptor_point_compressed']['high']},
}};

const DLEQ_ADAPTOR_POINT_SQRT_HINT: u256 = u256 {{
    low: {proof['adaptor_point_sqrt_hint']['low']},
    high: {proof['adaptor_point_sqrt_hint']['high']},
}};

// ... (rest of constants)
"""
        
        if args.output_file:
            with open(args.output_file, 'w') as f:
                f.write(output)
            print(f"✓ DLEQ proof written to {args.output_file}")
        else:
            print(output)
            
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()

