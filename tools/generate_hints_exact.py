#!/usr/bin/env python3
"""
Generate DLEQ hints using EXACT Garaga decompression.

CRITICAL: This uses Garaga's decompress function to get the EXACT
Weierstrass coordinates that Cairo will use, not scalar multiplication.
"""

import json
import sys
from pathlib import Path

try:
    from garaga.hints.fake_glv import get_fake_glv_hint
    from garaga.points import G1Point
    from garaga.curves import CurveID, CURVES
    GARAGA_AVAILABLE = True
except ImportError:
    print("ERROR: garaga package not found")
    print("Install with: pip install garaga")
    sys.exit(1)

ED25519_ORDER = 2**252 + 27742317777372353535851937790883648493
ED25519_CURVE_INDEX = 4


def hex_to_u256(hex_str: str) -> tuple[int, int]:
    """Convert hex string to (low, high) u128 pair."""
    value = int(hex_str, 16)
    low = value & ((1 << 128) - 1)
    high = value >> 128
    return low, high


def decompress_with_garaga(compressed_hex: str, sqrt_hint_low: int, sqrt_hint_high: int):
    """
    Decompress Edwards point using Garaga's EXACT algorithm.
    Returns G1Point in Weierstrass coordinates.
    
    This matches Cairo's decompress_edwards_pt_from_y_compressed_le_into_weirstrasspoint.
    """
    curve = CURVES[CurveID.ED25519.value]
    p = curve.p  # Ed25519 prime
    d = curve.d_twisted  # Edwards d coefficient
    
    # Extract sign bit and y-coordinate from compressed point (little-endian bytes)
    compressed_hex_clean = compressed_hex.replace('0x', '')
    compressed_bytes = bytes.fromhex(compressed_hex_clean)
    compressed_int = int.from_bytes(compressed_bytes, 'little')
    
    sign_bit = (compressed_int >> 255) & 1
    y = compressed_int & ((1 << 255) - 1)
    
    # Reconstruct x from sqrt hint (u256 format: low | (high << 128))
    # The sqrt hint IS the x-coordinate (twisted Edwards)
    x = sqrt_hint_low | (sqrt_hint_high << 128)
    x = x % p
    
    # Verify sqrt hint: x^2 should equal (y^2 - 1) / (d*y^2 + 1)
    y2 = (y * y) % p
    numerator = (y2 - 1) % p
    denominator = (d * y2 + 1) % p
    denominator_inv = pow(denominator, p - 2, p)  # Fermat's little theorem
    x2_expected = (numerator * denominator_inv) % p
    x2_actual = (x * x) % p
    
    # Garaga checks: sqrt_hint.low % 2 == sign_bit
    # If mismatch, negate x (Garaga does this internally)
    if (x % 2) != sign_bit:
        x = (p - x) % p
        x2_actual = (x * x) % p
    
    # Verify x^2 matches expected value
    if x2_actual != x2_expected:
        # Try the other square root
        x_alt = (p - x) % p
        x2_alt = (x_alt * x_alt) % p
        if x2_alt == x2_expected:
            x = x_alt
            x2_actual = x2_alt
        else:
            raise AssertionError(f"Invalid sqrt hint: x^2 = {hex(x2_actual)}, expected {hex(x2_expected)}")
    
    # Convert Edwards (x, y) to Weierstrass coordinates using Garaga's conversion
    edwards_point = curve.to_weierstrass(x, y)
    
    # Create G1Point from Weierstrass coordinates
    return G1Point(edwards_point[0], edwards_point[1], curve_id=CurveID.ED25519)


def u384_to_limbs(value: int) -> list[int]:
    """Convert u384 to 4 x 96-bit limbs."""
    MASK_96 = (1 << 96) - 1
    return [
        (value >> (96 * i)) & MASK_96
        for i in range(4)
    ]


def main():
    # Load test vectors
    vectors_path = Path(__file__).parent.parent / "rust" / "test_vectors.json"
    if not vectors_path.exists():
        print(f"ERROR: {vectors_path} not found")
        sys.exit(1)
    
    with open(vectors_path) as f:
        vectors = json.load(f)
    
    print("=" * 80)
    print("GENERATING HINTS WITH EXACT GARAGA DECOMPRESSION")
    print("=" * 80)
    
    # Get sqrt hints from test vectors
    # Parse correctly - these are already integers in the JSON
    adaptor_sqrt_low = int(vectors["adaptor_point_sqrt_hint_u256"]["low"], 16)
    adaptor_sqrt_high = int(vectors["adaptor_point_sqrt_hint_u256"]["high"], 16)
    
    second_sqrt_low = int(vectors["second_point_sqrt_hint_u256"]["low"], 16)
    second_sqrt_high = int(vectors["second_point_sqrt_hint_u256"]["high"], 16)
    
    # Step 1: Decompress T and U using GARAGA'S EXACT ALGORITHM
    print("\n### DECOMPRESSING POINTS WITH GARAGA ###\n")
    
    T = decompress_with_garaga(
        vectors["adaptor_point_compressed"],
        adaptor_sqrt_low,
        adaptor_sqrt_high
    )
    print(f"T (Weierstrass): x=0x{T.x:x}, y=0x{T.y:x}")
    
    U = decompress_with_garaga(
        vectors["second_point_compressed"],
        second_sqrt_low,
        second_sqrt_high
    )
    print(f"U (Weierstrass): x=0x{U.x:x}, y=0x{U.y:x}")
    
    # Step 2: Get G and Y (these should match Cairo's hardcoded values)
    G = G1Point.get_nG(CurveID.ED25519, 1)
    Y = G.scalar_mul(2)  # Y = 2*G
    
    print(f"\nG (Weierstrass): x=0x{G.x:x}")
    print(f"Y (Weierstrass): x=0x{Y.x:x}")
    
    # Step 3: Get truncated scalars (matching Cairo's reduce_felt_to_scalar)
    response_int = int(vectors["response"], 16)
    challenge_int = int(vectors["challenge"], 16)
    
    # Cairo truncates to 128 bits
    s_scalar = response_int & ((1 << 128) - 1)
    c_scalar = challenge_int & ((1 << 128) - 1)
    c_neg_scalar = (ED25519_ORDER - c_scalar) % ED25519_ORDER
    
    print(f"\n### SCALARS (128-bit truncated) ###")
    print(f"s:   0x{s_scalar:032x}")
    print(f"c:   0x{c_scalar:032x}")
    print(f"-c:  0x{c_neg_scalar:064x}")
    
    # Step 4: Generate hints using EXACT Weierstrass coordinates
    print("\n### GENERATING MSM HINTS ###\n")
    
    # s*G hint
    Q_sG, s1_sG, s2_sG = get_fake_glv_hint(G, s_scalar)
    sG_hint = u384_to_limbs(Q_sG.x) + u384_to_limbs(Q_sG.y) + [s1_sG, s2_sG]
    
    # s*Y hint
    Q_sY, s1_sY, s2_sY = get_fake_glv_hint(Y, s_scalar)
    sY_hint = u384_to_limbs(Q_sY.x) + u384_to_limbs(Q_sY.y) + [s1_sY, s2_sY]
    
    # (-c)*T hint - using EXACT decompressed T
    Q_negcT, s1_negcT, s2_negcT = get_fake_glv_hint(T, c_neg_scalar)
    negcT_hint = u384_to_limbs(Q_negcT.x) + u384_to_limbs(Q_negcT.y) + [s1_negcT, s2_negcT]
    
    # (-c)*U hint - using EXACT decompressed U
    Q_negcU, s1_negcU, s2_negcU = get_fake_glv_hint(U, c_neg_scalar)
    negcU_hint = u384_to_limbs(Q_negcU.x) + u384_to_limbs(Q_negcU.y) + [s1_negcU, s2_negcU]
    
    # Print Cairo code
    print("// Copy these to test_e2e_dleq.cairo")
    print()
    
    hints = {
        "s_hint_for_g": sG_hint,
        "s_hint_for_y": sY_hint,
        "c_neg_hint_for_t": negcT_hint,
        "c_neg_hint_for_u": negcU_hint,
    }
    
    for name, hint in hints.items():
        print(f"let {name}: Span<felt252> = array![")
        for i, v in enumerate(hint):
            comma = "," if i < 9 else ""
            print(f"    0x{v:x}{comma}")
        print("].span();")
        print()
    
    print("=" * 80)
    print("VERIFICATION: T and U above must match Cairo's decompressed coordinates!")
    print("=" * 80)


if __name__ == "__main__":
    main()

