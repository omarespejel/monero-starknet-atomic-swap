#!/usr/bin/env python3
"""
Generate fake-GLV hint for adaptor point MSM verification.

This script generates the correct s1/s2 decomposition for the scalar
used in MSM verification: scalar·G == adaptor_point

The scalar is derived from SHA-256(secret) → hashlock → u256 → mod Ed25519 order.
"""

import json
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from garaga import garaga_rs
    from garaga.curves import CurveID, CURVES
except ImportError:
    print("ERROR: garaga package not found. Install with: pip install garaga")
    sys.exit(1)


def hashlock_to_scalar(hashlock_bytes: bytes) -> int:
    """
    Convert hashlock (32 bytes) to u256 scalar, matching Cairo's hash_to_scalar_u256.
    
    Interprets bytes as little-endian u256: h0 + h1·2^32 + ... + h7·2^224
    Then reduces mod Ed25519 order.
    """
    # Convert bytes to u32 words (little-endian)
    words = []
    for i in range(0, 32, 4):
        word = int.from_bytes(hashlock_bytes[i:i+4], byteorder='little')
        words.append(word)
    
    # Build u256: h0 + h1·2^32 + h2·2^64 + ... + h7·2^224
    scalar = 0
    for i, word in enumerate(words):
        scalar += word * (2 ** (32 * i))
    
    # Reduce mod Ed25519 order
    curve = CURVES[CurveID.ED25519.value]
    ed25519_order = curve.order
    scalar = scalar % ed25519_order
    
    return scalar


def generate_adaptor_point_hint(
    test_vectors_path: str = "../rust/test_vectors.json",
    output_path: str = "../cairo/adaptor_point_hint.json"
):
    """
    Generate fake-GLV hint for adaptor point MSM: scalar·G == adaptor_point
    
    Args:
        test_vectors_path: Path to test_vectors.json containing hashlock and adaptor point
        output_path: Path to save generated hint
    """
    # Load test vectors
    with open(test_vectors_path, 'r') as f:
        vectors = json.load(f)
    
    # Extract hashlock (as hex string, convert to bytes)
    hashlock_hex = vectors['hashlock']
    if isinstance(hashlock_hex, str):
        # Remove '0x' prefix if present
        hashlock_hex = hashlock_hex.replace('0x', '')
        hashlock_bytes = bytes.fromhex(hashlock_hex)
    else:
        # Assume it's already a list of u32 values
        hashlock_bytes = b''.join([v.to_bytes(4, 'little') for v in hashlock_hex])
    
    # Convert hashlock to scalar (matches Cairo's hash_to_scalar_u256)
    scalar = hashlock_to_scalar(hashlock_bytes)
    
    print(f"Hashlock scalar: {hex(scalar)}")
    print(f"Scalar (decimal): {scalar}")
    
    # Get Ed25519 generator G (Weierstrass coordinates)
    curve = CURVES[CurveID.ED25519.value]
    G_x = curve.Gx
    G_y = curve.Gy
    
    print(f"\nEd25519 Generator G:")
    print(f"  G.x: {hex(G_x)}")
    print(f"  G.y: {hex(G_y)}")
    
    # Extract adaptor point coordinates from test vectors
    # The adaptor point is stored as compressed Edwards, we need to decompress it
    # For now, we'll use Garaga's decompression
    adaptor_compressed_hex = vectors['adaptor_point_compressed']
    if isinstance(adaptor_compressed_hex, str):
        adaptor_compressed_hex = adaptor_compressed_hex.replace('0x', '')
        adaptor_compressed_bytes = bytes.fromhex(adaptor_compressed_hex)
    else:
        # Convert u256 to bytes (little-endian)
        adaptor_compressed_bytes = adaptor_compressed_hex.to_bytes(32, 'little')
    
    # Decompress adaptor point (this requires Garaga's decompression)
    # For now, we'll use the fact that we know scalar·G = adaptor_point
    # So we can compute adaptor_point = scalar * G using Garaga
    
    # Use Garaga's MSM calldata builder to generate the hint
    # This will compute the correct s1/s2 decomposition
    print(f"\nGenerating fake-GLV hint using garaga_rs.msm_calldata_builder...")
    
    # Build MSM calldata with proper decomposition
    msm_calldata = garaga_rs.msm_calldata_builder(
        [G_x, G_y],  # Points: [G]
        [scalar],    # Scalars: [scalar]
        CurveID.ED25519.value,
        False,  # include_points_and_scalars
        True,   # serialize_as_pure_felt252_array
    )
    
    # Extract the hint from calldata
    # The hint format is: [Q.x[4], Q.y[4], s1, s2]
    # MSM calldata includes the hint as the last elements
    hint = msm_calldata[-10:]  # Last 10 felts are the hint
    
    print(f"\nGenerated hint (10 felts):")
    for i, felt in enumerate(hint):
        print(f"  hint[{i}]: 0x{felt:x}")
    
    # Verify: Extract Q from hint
    Q_x_limbs = hint[0:4]
    Q_y_limbs = hint[4:8]
    s1 = hint[8]
    s2 = hint[9]
    
    print(f"\nHint breakdown:")
    print(f"  Q.x limbs: {[hex(x) for x in Q_x_limbs]}")
    print(f"  Q.y limbs: {[hex(y) for y in Q_y_limbs]}")
    print(f"  s1: 0x{s1:x}")
    print(f"  s2: 0x{s2:x}")
    
    # Verify s1/s2 decomposition: s2·scalar ≡ s1 (mod r)
    ed25519_order = curve.order
    verification = (s2 * scalar) % ed25519_order
    print(f"\nVerification:")
    print(f"  s2·scalar mod r: 0x{verification:x}")
    print(f"  s1:               0x{s1:x}")
    print(f"  Match: {verification == s1}")
    
    # Save to file
    output_data = {
        "adaptor_point_hint": hint,
        "scalar": hex(scalar),
        "cairo_format": f"array![{', '.join(f'0x{felt:x}' for felt in hint)}].span()"
    }
    
    with open(output_path, 'w') as f:
        json.dump(output_data, f, indent=2)
    
    print(f"\n✅ Hint saved to {output_path}")
    print(f"\nCairo format:")
    print(output_data["cairo_format"])
    
    return hint


if __name__ == '__main__':
    hint = generate_adaptor_point_hint()

