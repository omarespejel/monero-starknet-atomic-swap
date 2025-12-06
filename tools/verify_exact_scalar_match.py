#!/usr/bin/env python3
"""
Verify Python hint generation matches Cairo's exact scalar values.

This script calculates what Cairo SHOULD compute and generates hints
for those exact values, providing ground truth for debugging.
"""

import json
from pathlib import Path

# Import Garaga
try:
    from garaga.hints.fake_glv import get_fake_glv_hint
    from garaga.curves import CurveID, CURVES
    from garaga.points import G1Point
except ImportError:
    print("ERROR: garaga package not found.")
    print("Install with: uv pip install --python 3.10 garaga==1.0.1")
    exit(1)

# Ed25519 order
ed25519_order = 2**252 + 27742317777372353535851937790883648493
curve = CURVES[CurveID.ED25519.value]
G = G1Point.get_nG(CurveID.ED25519, 1)

print("=" * 80)
print("PYTHON GROUND TRUTH: Scalar Values and Hints")
print("=" * 80)
print()

# Response scalar
response_hex = "0850ef802e40bbd177b22dd7319a9bc047cff7b5713428a889bfad01f6fa4e00"
response_int = int(response_hex, 16)

print("RESPONSE SCALAR:")
print(f"  Full hex: {response_hex}")
print(f"  Full int: {response_int}")
print()

# Step 1: What does reduce_felt_to_scalar produce?
response_reduced = response_int % ed25519_order
print(f"  response % order = 0x{response_reduced:064x}")
print(f"  Decimal: {response_reduced}")
print()

# Step 2: Split into u256 (low 128, high 128)
scalar_low = response_reduced & ((1 << 128) - 1)
scalar_high = (response_reduced >> 128) & ((1 << 128) - 1)
print(f"  scalar.low  = 0x{scalar_low:032x}")
print(f"  scalar.high = 0x{scalar_high:032x}")
print()

# Step 3: What does Garaga receive? (felt252.into::<u384>)
# This should be response_reduced, but verify with Cairo test output
print(f"  Garaga should receive u384: {response_reduced}")
print()

# Step 4: Generate hint for THIS EXACT VALUE
print("Generating hint for response scalar...")
Q_response, s1_response, s2_response = get_fake_glv_hint(G, response_reduced)
print(f"  Q.x: 0x{Q_response.x:x}")
print(f"  Q.y: 0x{Q_response.y:x}")
print(f"  s1:  {s1_response}")
print(f"  s2:  {s2_response}")
print()

# Step 5: Verify decomposition
s2_signed = s2_response if s2_response < (1 << 127) else -(s2_response - (1 << 128))
check = (s1_response + response_reduced * s2_signed) % curve.n
print(f"  Verification: (s1 + scalar*s2) % order = {check}")
print("  ✅ VALID" if check == 0 else "  ❌ INVALID")
print()

# Challenge scalar
challenge_hex = "c53365223a31a1e310296fda3ed593ff6212e6122afa3670f0f578dffd3b2703"
challenge_int = int(challenge_hex, 16)

print("CHALLENGE SCALAR:")
print(f"  Full hex: {challenge_hex}")
print(f"  Full int: {challenge_int}")
print()

challenge_reduced = challenge_int % ed25519_order
print(f"  challenge % order = 0x{challenge_reduced:064x}")
print(f"  Decimal: {challenge_reduced}")
print()

challenge_low = challenge_reduced & ((1 << 128) - 1)
challenge_high = (challenge_reduced >> 128) & ((1 << 128) - 1)
print(f"  scalar.low  = 0x{challenge_low:032x}")
print(f"  scalar.high = 0x{challenge_high:032x}")
print()

# -c mod order
c_neg = (ed25519_order - challenge_reduced) % ed25519_order
print(f"  -c mod order = 0x{c_neg:064x}")
print()

# Generate hint for -c
print("Generating hint for -c scalar...")
# We need T point for this - load from test vectors
test_vectors_path = Path(__file__).parent.parent / "rust" / "test_vectors.json"
with open(test_vectors_path) as f:
    vectors = json.load(f)

# Decompress T (adaptor_point) - simplified, using known point
# For now, just show the scalar value
print(f"  -c scalar: 0x{c_neg:064x}")
print()

# Compare with current hints in test file
print("=" * 80)
print("COMPARISON WITH CURRENT HINTS")
print("=" * 80)
print()
print("Current hints in test_e2e_dleq.cairo:")
print("  s_hint_for_g Q coordinates (from hint):")
print("    Check if Q matches expected Q_response above")
print()
print("  c_neg_hint_for_t:")
print("    Check if scalar matches -c above")
print()

# Output Cairo test constants
print("=" * 80)
print("CAIRO TEST CONSTANTS (for comparison)")
print("=" * 80)
print()
print("Response scalar (felt252):")
print(f"  BASE_128: 0x100000000000000000000000000000000")
print(f"  RESPONSE_LOW: 0x{scalar_low:032x}")
print(f"  RESPONSE_HIGH: 0x{scalar_high:032x}")
print(f"  Full scalar: 0x{response_reduced:064x}")
print()
print("Challenge scalar (felt252):")
print(f"  CHALLENGE_LOW: 0x{challenge_low:032x}")
print(f"  CHALLENGE_HIGH: 0x{challenge_high:032x}")
print(f"  Full scalar: 0x{challenge_reduced:064x}")
print()

