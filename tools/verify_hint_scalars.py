#!/usr/bin/env python3
"""
Verify that s1/s2 in hints match Garaga's internal GLV decomposition.
"""

import json
from pathlib import Path

try:
    from garaga.hints.fake_glv import get_fake_glv_hint
    from garaga.points import G1Point
    from garaga.curves import CurveID
except ImportError:
    print("ERROR: garaga not found. Install: pip install garaga")
    exit(1)

ED25519_ORDER = 2**252 + 27742317777372353535851937790883648493

# Load test vectors
vectors_path = Path(__file__).parent.parent / "rust" / "test_vectors.json"
with open(vectors_path) as f:
    vectors = json.load(f)

response_int = int(vectors["response"], 16)
challenge_int = int(vectors["challenge"], 16)

# Cairo truncates to 128 bits
s_scalar = response_int & ((1 << 128) - 1)
c_scalar = challenge_int & ((1 << 128) - 1)
c_neg_scalar = (ED25519_ORDER - c_scalar) % ED25519_ORDER

print("=" * 80)
print("VERIFYING s1/s2 DECOMPOSITION IN HINTS")
print("=" * 80)

# Get G and Y
G = G1Point.get_nG(CurveID.ED25519, 1)
Y = G.scalar_mul(2)  # Y = 2*G

# Compute hints and extract s1/s2
_, s1_sG, s2_sG = get_fake_glv_hint(G, s_scalar)
_, s1_sY, s2_sY = get_fake_glv_hint(Y, s_scalar)

print(f"\nExpected from Garaga:")
print(f"  s*G: s1=0x{s1_sG:032x}, s2=0x{s2_sG:032x}")
print(f"  s*Y: s1=0x{s1_sY:032x}, s2=0x{s2_sY:032x}")

# Load hints from test_e2e_dleq.cairo (manually parse or hardcode)
# These are the ACTUAL hints your test is using
s_hint_for_g = [
    0xd21de05d0b4fe220a6fcca9b,
    0xa8e827ce9b59e1a5770bd9a,
    0x4e14ea0d8a7581a1,
    0x0,
    0x8cfb1d3e412e174d0ad03ad4,
    0x4417fe7cc6824de3b328f2a0,
    0x13f6f393b443ac08,
    0x0,
    0x1fd0f994a4c11a4543d86f4578e7b9ed,  # s1
    0x39099b31d1013f73ec51ebd61fdfe2ab,  # s2
]

s_hint_for_y = [
    0xcdb4e41a66188ec060e0e45b,
    0x1cf0f0ff51495823cad8d964,
    0x2dcda3d3bbeda8a3,
    0x0,
    0x8b8b33d4304cc1bedc45545c,
    0x5fbf8dbd7bd2029ba859c5bb,
    0x145b0ef370c62319,
    0x0,
    0x1fd0f994a4c11a4543d86f4578e7b9ed,  # s1
    0x39099b31d1013f73ec51ebd61fdfe2ab,  # s2
]

print(f"\nActual from hints (s*G):")
print(f"  s1=0x{s_hint_for_g[8]:032x}")
print(f"  s2=0x{s_hint_for_g[9]:032x}")

print(f"\nActual from hints (s*Y):")
print(f"  s1=0x{s_hint_for_y[8]:032x}")
print(f"  s2=0x{s_hint_for_y[9]:032x}")

# Verify s*G
print("\n" + "=" * 80)
print("VERIFICATION: s*G")
print("=" * 80)
if s1_sG == s_hint_for_g[8] and s2_sG == s_hint_for_g[9]:
    print("✅ s*G scalars MATCH")
else:
    print("❌ s*G scalars MISMATCH")
    print(f"   Expected s1: 0x{s1_sG:032x}")
    print(f"   Got s1:      0x{s_hint_for_g[8]:032x}")
    print(f"   Expected s2: 0x{s2_sG:032x}")
    print(f"   Got s2:      0x{s_hint_for_g[9]:032x}")

# Verify s*Y
print("\n" + "=" * 80)
print("VERIFICATION: s*Y")
print("=" * 80)
if s1_sY == s_hint_for_y[8] and s2_sY == s_hint_for_y[9]:
    print("✅ s*Y scalars MATCH")
else:
    print("❌ s*Y scalars MISMATCH")
    print(f"   Expected s1: 0x{s1_sY:032x}")
    print(f"   Got s1:      0x{s_hint_for_y[8]:032x}")
    print(f"   Expected s2: 0x{s2_sY:032x}")
    print(f"   Got s2:      0x{s_hint_for_y[9]:032x}")

# Now check (-c)*T and (-c)*U
# We need to decompress T and U first
def decompress_with_garaga(compressed_hex: str, sqrt_hint_low: int, sqrt_hint_high: int):
    """
    Decompress Edwards point using Garaga's EXACT algorithm.
    Returns G1Point in Weierstrass coordinates.
    """
    from garaga.curves import CURVES
    
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
        else:
            raise AssertionError(f"Invalid sqrt hint: x^2 = {hex(x2_actual)}, expected {hex(x2_expected)}")
    
    # Convert Edwards (x, y) to Weierstrass coordinates using Garaga's conversion
    edwards_point = curve.to_weierstrass(x, y)
    
    # Create G1Point from Weierstrass coordinates
    return G1Point(edwards_point[0], edwards_point[1], curve_id=CurveID.ED25519)

adaptor_sqrt_low = int(vectors["adaptor_point_sqrt_hint_u256"]["low"], 16)
adaptor_sqrt_high = int(vectors["adaptor_point_sqrt_hint_u256"]["high"], 16)
second_sqrt_low = int(vectors["second_point_sqrt_hint_u256"]["low"], 16)
second_sqrt_high = int(vectors["second_point_sqrt_hint_u256"]["high"], 16)

T = decompress_with_garaga(
    vectors["adaptor_point_compressed"],
    adaptor_sqrt_low,
    adaptor_sqrt_high
)

U = decompress_with_garaga(
    vectors["second_point_compressed"],
    second_sqrt_low,
    second_sqrt_high
)

_, s1_negcT, s2_negcT = get_fake_glv_hint(T, c_neg_scalar)
_, s1_negcU, s2_negcU = get_fake_glv_hint(U, c_neg_scalar)

print(f"\nExpected from Garaga:")
print(f"  (-c)*T: s1=0x{s1_negcT:032x}, s2=0x{s2_negcT:032x}")
print(f"  (-c)*U: s1=0x{s1_negcU:032x}, s2=0x{s2_negcU:032x}")

c_neg_hint_for_t = [
    0x959983489a84cf6bb55fde22,
    0xfbea3c47483b8fb99b0e29ef,
    0x3fe816922486f803,
    0x0,
    0x406a020256217f7a00633c4a,
    0x6b9be390479e99c682cae8f0,
    0x7b48b6a59c2c6732,
    0x0,
    0x208a4ac47d492a7b82475d0c0c798e52,  # s1
    0x29c3b379b559be107e5c78bb9abb6515,  # s2
]

c_neg_hint_for_u = [
    0x6bea23ab976cb56319ceb69d,
    0xba4983a65676829fc603f500,
    0x65b0b083f90952f1,
    0x0,
    0x7e7a6ae6e23418c184e6d824,
    0x119cf240405f414ec4ed2cc6,
    0x15cea0344fcb9e58,
    0x0,
    0x208a4ac47d492a7b82475d0c0c798e52,  # s1
    0x29c3b379b559be107e5c78bb9abb6515,  # s2
]

print(f"\nActual from hints ((-c)*T):")
print(f"  s1=0x{c_neg_hint_for_t[8]:032x}")
print(f"  s2=0x{c_neg_hint_for_t[9]:032x}")

print(f"\nActual from hints ((-c)*U):")
print(f"  s1=0x{c_neg_hint_for_u[8]:032x}")
print(f"  s2=0x{c_neg_hint_for_u[9]:032x}")

# Verify (-c)*T
print("\n" + "=" * 80)
print("VERIFICATION: (-c)*T")
print("=" * 80)
if s1_negcT == c_neg_hint_for_t[8] and s2_negcT == c_neg_hint_for_t[9]:
    print("✅ (-c)*T scalars MATCH")
else:
    print("❌ (-c)*T scalars MISMATCH")
    print(f"   Expected s1: 0x{s1_negcT:032x}")
    print(f"   Got s1:      0x{c_neg_hint_for_t[8]:032x}")
    print(f"   Expected s2: 0x{s2_negcT:032x}")
    print(f"   Got s2:      0x{c_neg_hint_for_t[9]:032x}")

# Verify (-c)*U
print("\n" + "=" * 80)
print("VERIFICATION: (-c)*U")
print("=" * 80)
if s1_negcU == c_neg_hint_for_u[8] and s2_negcU == c_neg_hint_for_u[9]:
    print("✅ (-c)*U scalars MATCH")
else:
    print("❌ (-c)*U scalars MISMATCH")
    print(f"   Expected s1: 0x{s1_negcU:032x}")
    print(f"   Got s1:      0x{c_neg_hint_for_u[8]:032x}")
    print(f"   Expected s2: 0x{s2_negcU:032x}")
    print(f"   Got s2:      0x{c_neg_hint_for_u[9]:032x}")

print("\n" + "=" * 80)
print("SUMMARY")
print("=" * 80)

