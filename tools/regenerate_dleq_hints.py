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
    
    s_scalar = response_int % order
    c_scalar = challenge_int % order
    c_neg_scalar = (order - c_scalar) % order
    
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
    
    # For T and U, we need to decompress from test vectors
    # But we can't easily do that from Python without Garaga bindings
    # Instead, let's use the fact that T = secret·G and U = secret·Y
    # We can compute these from the secret scalar
    
    secret_hex = vectors['secret']
    secret_bytes = bytes.fromhex(secret_hex)
    secret_int = int.from_bytes(secret_bytes, 'little')
    secret_scalar = secret_int % order
    
    T = G.scalar_mul(secret_scalar)  # T = secret·G
    U = Y.scalar_mul(secret_scalar)  # U = secret·Y
    
    print(f"Adaptor point T (secret·G):")
    print(f"  T.x: 0x{T.x:x}")
    print(f"  T.y: 0x{T.y:x}")
    print()
    print(f"Second point U (secret·Y):")
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

