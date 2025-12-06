#!/usr/bin/env python3
"""Verify the generated hint is mathematically correct"""

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from garaga.curves import CurveID, CURVES
from garaga.hints.fake_glv import get_fake_glv_hint
from garaga.points import G1Point

# Load generated hint
with open("../cairo/adaptor_point_hint.json", 'r') as f:
    data = json.load(f)

scalar = int(data['scalar'], 16)
hint = data['adaptor_point_hint']

# Get curve
curve = CURVES[CurveID.ED25519.value]
G = G1Point.get_nG(CurveID.ED25519, 1)

# Verify hint was generated correctly
Q, s1, s2_encoded = get_fake_glv_hint(G, scalar)

# Convert Q to limbs
def u384_to_limbs(value: int) -> list[int]:
    """Convert u384 to 4 u96 limbs."""
    mask_96 = (1 << 96) - 1
    return [
        value & mask_96,
        (value >> 96) & mask_96,
        (value >> 192) & mask_96,
        (value >> 288) & mask_96,
    ]

Q_x_limbs = u384_to_limbs(Q.x)
Q_y_limbs = u384_to_limbs(Q.y)
expected_hint = [*Q_x_limbs, *Q_y_limbs, s1, s2_encoded]

# Compare hints
if hint != expected_hint:
    print("❌ Hint mismatch!")
    print(f"Generated: {hint[:4]}...")
    print(f"Expected:  {expected_hint[:4]}...")
    sys.exit(1)

# Extract hint components
Q_x_limbs = hint[0:4]
Q_y_limbs = hint[4:8]
s1 = hint[8]
s2 = hint[9]

# Reconstruct Q from limbs (simplified check)
print("✓ Hint format correct: 10 felts")
print(f"✓ Scalar: 0x{scalar:064x}")
print(f"✓ Q.x limbs: {[hex(x) for x in Q_x_limbs]}")
print(f"✓ Q.y limbs: {[hex(y) for y in Q_y_limbs]}")
print(f"✓ s1: 0x{s1:032x}")
print(f"✓ s2: 0x{s2:032x}")

# Verify s2 * scalar ≡ s1 (mod curve.n)
verification = (s2 * scalar) % curve.n
s1_mod_n = s1 % curve.n

if verification != s1_mod_n:
    print(f"\n❌ Decomposition invalid!")
    print(f"  (s2*scalar) mod n = 0x{verification:032x}")
    print(f"  s1 mod n         = 0x{s1_mod_n:032x}")
    sys.exit(1)

print(f"✓ Decomposition valid: s2·scalar ≡ s1 (mod n)")
print(f"  (s2*scalar) mod n = 0x{verification:032x}")
print(f"  s1 mod n         = 0x{s1_mod_n:032x}")

# Verify Q = scalar·G
computed_Q = G.scalar_mul(scalar)
if Q != computed_Q:
    print(f"\n❌ Q mismatch!")
    print(f"  Q from hint: ({hex(Q.x)}, {hex(Q.y)})")
    print(f"  scalar·G:    ({hex(computed_Q.x)}, {hex(computed_Q.y)})")
    sys.exit(1)

print(f"✓ Q matches scalar·G")

print("\n✅ All verifications passed!")

