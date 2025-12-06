#!/usr/bin/env python3
"""
Regenerate DLEQ hints for new test vectors.

This script generates fake-GLV hints for DLEQ verification scalars:
- s (response scalar)
- -c (negated challenge scalar)

Using actual T and U points from regenerated test_vectors.json.
"""

import json
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from garaga.hints.fake_glv import get_fake_glv_hint
    from garaga.curves import CurveID, CURVES
    from garaga.points import G1Point
except ImportError:
    print("ERROR: garaga package not found.")
    print("Install with: uv pip install --python 3.10 garaga==1.0.1")
    print("Note: garaga requires Python 3.10. If using uv:")
    print("  uv python install 3.10")
    print("  uv pip install --python 3.10 garaga==1.0.1")
    sys.exit(1)

def u384_to_limbs(value: int) -> list[int]:
    """Convert u384 to 4 u96 limbs."""
    mask_96 = (1 << 96) - 1
    return [
        value & mask_96,
        (value >> 96) & mask_96,
        (value >> 192) & mask_96,
        (value >> 288) & mask_96,
    ]

def hex_to_u256(hex_str: str) -> tuple[int, int]:
    """Convert 32-byte hex string to u256 (low, high)."""
    hex_str = hex_str.replace('0x', '')
    bytes_val = bytes.fromhex(hex_str)
    low = int.from_bytes(bytes_val[:16], 'little')
    high = int.from_bytes(bytes_val[16:], 'little')
    return (low, high)

def decompress_point(compressed_hex: str, sqrt_hint_hex: str) -> G1Point:
    """Decompress Edwards point using sqrt hint."""
    # Convert to u256 format
    compressed_low, compressed_high = hex_to_u256(compressed_hex)
    hint_low, hint_high = hex_to_u256(sqrt_hint_hex)
    
    # Create u256 values
    compressed_u256 = (compressed_low, compressed_high)
    hint_u256 = (hint_low, hint_high)
    
    # Decompress (this is a placeholder - actual decompression needs Garaga's function)
    # For now, we'll use Garaga's Python API if available
    # Otherwise, we'll need to compute from compressed + hint
    
    # Actually, we can use the decompressed coordinates from test_vectors.json
    # if they're stored, or we need to use Garaga's decompression
    
    # Workaround: Use Garaga's decompression via Python API
    # This requires the actual Garaga Python bindings
    
    # For now, let's use a different approach: generate hints using the scalar
    # and base points, which we can compute
    
    raise NotImplementedError("Point decompression from Python needs Garaga bindings")

def main():
    """Regenerate DLEQ hints from test_vectors.json."""
    script_dir = Path(__file__).parent
    test_vectors_path = script_dir.parent / "rust" / "test_vectors.json"
    
    if not test_vectors_path.exists():
        print(f"Error: {test_vectors_path} not found")
        sys.exit(1)
    
    with open(test_vectors_path, 'r') as f:
        vectors = json.load(f)
    
    # Extract scalars
    response_hex = vectors['response']
    challenge_hex = vectors['challenge']
    
    response_int = int(response_hex, 16)
    challenge_int = int(challenge_hex, 16)
    
    # Ed25519 order
    curve = CURVES[CurveID.ED25519.value]
    order = curve.n
    
    # CRITICAL: Cairo passes full felt252 scalars (reduced mod order) to msm_g1
    # reduce_felt_to_scalar converts felt252 -> u128 -> u256, then reduces mod order
    # The scalar passed to Garaga is: (felt252 as u128) % order
    # NOT truncated to u128 before reduction - use FULL values reduced mod order
    
    # CORRECT: Use full values reduced mod order (NO .low truncation!)
    s_scalar = response_int % order
    c_scalar = challenge_int % order
    c_neg_scalar = (order - c_scalar) % order
    
    print(f"Using full scalars (reduced mod order, no truncation):")
    print(f"  Response scalar s: 0x{s_scalar:064x}")
    print(f"  Challenge scalar c: 0x{c_scalar:064x}")
    print(f"  -c mod order: 0x{c_neg_scalar:064x}")
    print()
    
    print("=" * 80)
    print("Regenerating DLEQ hints for new test vectors")
    print("=" * 80)
    print()
    print(f"Response scalar s: 0x{s_scalar:064x}")
    print(f"Challenge scalar c: 0x{c_scalar:064x}")
    print(f"-c mod order: 0x{c_neg_scalar:064x}")
    print()
    
    # Get base points
    G = G1Point.get_nG(CurveID.ED25519, 1)
    Y = G.scalar_mul(2)  # Y = 2·G
    
    # CRITICAL: Decompress T and U from test vectors using sqrt hints
    # Cairo will decompress these exact compressed points, so hints must match
    # those decompressed coordinates, not recomputed ones
    
    def decompress_edwards_point(compressed_hex: str, sqrt_hint_low: int, sqrt_hint_high: int) -> G1Point:
        """
        Decompress Edwards point using sqrt hint, matching Garaga's algorithm.
        
        This mirrors Cairo's decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point.
        Uses the same logic as regenerate_garaga_hints.py.
        """
        from garaga.curves import CurveID, CURVES
        
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
        # The sqrt hint IS the x-coordinate (from regenerate_garaga_hints.py)
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
    
    # Decompress adaptor_point (T) using sqrt hint
    adaptor_compressed_hex = vectors['adaptor_point_compressed']
    adaptor_sqrt_hint_low = int(vectors['adaptor_point_sqrt_hint_u256']['low'], 16)
    adaptor_sqrt_hint_high = int(vectors['adaptor_point_sqrt_hint_u256']['high'], 16)
    
    print("Decompressing adaptor_point (T) from test vectors...")
    T = decompress_edwards_point(adaptor_compressed_hex, adaptor_sqrt_hint_low, adaptor_sqrt_hint_high)
    print(f"  T.x: 0x{T.x:x}")
    print(f"  T.y: 0x{T.y:x}")
    print()
    
    # Decompress second_point (U) using sqrt hint
    second_compressed_hex = vectors['second_point_compressed']
    second_sqrt_hint_low = int(vectors['second_point_sqrt_hint_u256']['low'], 16)
    second_sqrt_hint_high = int(vectors['second_point_sqrt_hint_u256']['high'], 16)
    
    print("Decompressing second_point (U) from test vectors...")
    U = decompress_edwards_point(second_compressed_hex, second_sqrt_hint_low, second_sqrt_hint_high)
    print(f"  U.x: 0x{U.x:x}")
    print(f"  U.y: 0x{U.y:x}")
    print()
    
    # Generate hints
    print("Generating hints...")
    print()
    
    # s·G
    Q_sG, s1_sG, s2_sG = get_fake_glv_hint(G, s_scalar)
    sG_hint = [*u384_to_limbs(Q_sG.x), *u384_to_limbs(Q_sG.y), s1_sG, s2_sG]
    
    # s·Y
    Q_sY, s1_sY, s2_sY = get_fake_glv_hint(Y, s_scalar)
    sY_hint = [*u384_to_limbs(Q_sY.x), *u384_to_limbs(Q_sY.y), s1_sY, s2_sY]
    
    # (-c)·T
    Q_negcT, s1_negcT, s2_negcT = get_fake_glv_hint(T, c_neg_scalar)
    negcT_hint = [*u384_to_limbs(Q_negcT.x), *u384_to_limbs(Q_negcT.y), s1_negcT, s2_negcT]
    
    # (-c)·U
    Q_negcU, s1_negcU, s2_negcU = get_fake_glv_hint(U, c_neg_scalar)
    negcU_hint = [*u384_to_limbs(Q_negcU.x), *u384_to_limbs(Q_negcU.y), s1_negcU, s2_negcU]
    
    print("✅ Generated hints:")
    print()
    
    print("// s_hint_for_g: Fake-GLV hint for s·G")
    print(f"let s_hint_for_g = array![")
    for i, felt in enumerate(sG_hint):
        comma = "," if i < 9 else ""
        print(f"    0x{felt:x}{comma}")
    print("].span();")
    print()
    
    print("// s_hint_for_y: Fake-GLV hint for s·Y")
    print(f"let s_hint_for_y = array![")
    for i, felt in enumerate(sY_hint):
        comma = "," if i < 9 else ""
        print(f"    0x{felt:x}{comma}")
    print("].span();")
    print()
    
    print("// c_neg_hint_for_t: Fake-GLV hint for (-c)·T")
    print(f"let c_neg_hint_for_t = array![")
    for i, felt in enumerate(negcT_hint):
        comma = "," if i < 9 else ""
        print(f"    0x{felt:x}{comma}")
    print("].span();")
    print()
    
    print("// c_neg_hint_for_u: Fake-GLV hint for (-c)·U")
    print(f"let c_neg_hint_for_u = array![")
    for i, felt in enumerate(negcU_hint):
        comma = "," if i < 9 else ""
        print(f"    0x{felt:x}{comma}")
    print("].span();")
    print()
    
    # Verify decompositions
    print("=" * 80)
    print("Verification:")
    print("=" * 80)
    print()
    
    def verify_hint(scalar: int, s1: int, s2_encoded: int, name: str):
        """Verify hint decomposition."""
        # Decode s2
        if s2_encoded >= (1 << 128):
            s2_abs = s2_encoded - (1 << 128)
            s2_signed = -s2_abs
        else:
            s2_abs = s2_encoded
            s2_signed = s2_abs
        
        check = (s1 + scalar * s2_signed) % order
        if check == 0:
            print(f"✅ {name}: Valid decomposition")
        else:
            print(f"❌ {name}: Invalid decomposition (check = {check})")
    
    verify_hint(s_scalar, s1_sG, s2_sG, "s_hint_for_g")
    verify_hint(s_scalar, s1_sY, s2_sY, "s_hint_for_y")
    verify_hint(c_neg_scalar, s1_negcT, s2_negcT, "c_neg_hint_for_t")
    verify_hint(c_neg_scalar, s1_negcU, s2_negcU, "c_neg_hint_for_u")

if __name__ == "__main__":
    main()

