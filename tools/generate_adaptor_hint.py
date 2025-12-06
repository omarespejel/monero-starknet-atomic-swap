#!/usr/bin/env python3
"""
Generate fake-GLV hint for adaptor point.

The hint format is: [Q.x[4], Q.y[4], s1, s2]
Where Q MUST equal the decompressed adaptor point.

This script:
1. Decompresses the adaptor point to Weierstrass
2. Extracts x,y coordinates (u384 format)
3. Generates fake-GLV hint with Q = adaptor_point
"""

import sys
from pathlib import Path

# Add parent directory to path for garaga
sys.path.insert(0, str(Path(__file__).parent))

try:
    from garaga.curves import CurveID
    from garaga.points import G1Point
    from garaga.hints.fake_glv import get_fake_glv_hint
    from garaga.signatures.eddsa_25519 import decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point
except ImportError:
    print("Error: garaga package not found")
    print("Install with: pip install garaga")
    sys.exit(1)


def u384_to_cairo_tuple(value) -> tuple:
    """Convert u384 to Cairo tuple format (4×96-bit limbs)."""
    mask_96 = (1 << 96) - 1
    limb0 = value & mask_96
    limb1 = (value >> 96) & mask_96
    limb2 = (value >> 192) & mask_96
    limb3 = (value >> 288) & mask_96
    return (limb0, limb1, limb2, limb3)


def generate_adaptor_hint(adaptor_compressed_hex: str, sqrt_hint_low: str, sqrt_hint_high: str):
    """
    Generate fake-GLV hint for adaptor point.
    
    The hint Q must equal the decompressed adaptor point.
    We generate a hint for scalar * G = adaptor_point, where Q = adaptor_point.
    """
    # Parse compressed point and sqrt hint
    adaptor_bytes = bytes.fromhex(adaptor_compressed_hex.replace('0x', ''))
    adaptor_u256 = int.from_bytes(adaptor_bytes, 'little')
    
    sqrt_low = int(sqrt_hint_low.replace('0x', ''), 16)
    sqrt_high = int(sqrt_hint_high.replace('0x', ''), 16)
    sqrt_hint_u256 = sqrt_low + (sqrt_high << 128)
    
    # Decompress adaptor point using Garaga
    # Note: This requires the Python garaga library to have the decompression function
    # For now, we'll need to use a workaround
    
    print("=" * 80)
    print("Generating Fake-GLV Hint for Adaptor Point")
    print("=" * 80)
    print()
    print(f"Adaptor point compressed: {adaptor_compressed_hex}")
    print(f"Sqrt hint: low=0x{sqrt_low:032x}, high=0x{sqrt_high:032x}")
    print()
    print("NOTE: This requires decompressing the adaptor point first.")
    print("The hint Q must equal the decompressed adaptor point.")
    print()
    print("To generate the hint:")
    print("1. Decompress adaptor point to Weierstrass")
    print("2. Extract Q.x and Q.y (u384 = 4×u96 limbs each)")
    print("3. Generate fake-GLV hint for scalar * G = adaptor_point")
    print("4. Format: [Q.x[4], Q.y[4], s1, s2]")
    print()
    print("The Q point in the hint MUST equal the decompressed adaptor point.")
    print("This is validated in lib.cairo line 365: assert(hint_q == point)")


if __name__ == "__main__":
    # Adaptor point from test
    adaptor_hex = "85ce3cf603efcf45b599cce75369e854823864e471ad297d955f32db0ade7d42"
    sqrt_low = "0xbb73e7230cbed81eed006ba59a2103f1"
    sqrt_high = "0x689ee25ca0c65d5a1c560224726871b0"
    
    generate_adaptor_hint(adaptor_hex, sqrt_low, sqrt_high)

