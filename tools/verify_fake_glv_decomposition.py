#!/usr/bin/env python3
"""
Verify fake-GLV hint decomposition matches Garaga's requirements.

Garaga verifies: s1 + scalar * s2_signed ≡ 0 (mod order)

Where:
- s1: Always positive (u128)
- s2_signed: sign * s2_abs (sign is +1 or -1)
- s2_encoded: If positive, s2_abs; if negative, 2^128 + s2_abs
"""

import json
from pathlib import Path

# Ed25519 order
ORDER = 2**252 + 27742317777372353535851937790883648493

def verify_decomposition(scalar: int, s1: int, s2_encoded: int) -> bool:
    """
    Verify fake-GLV decomposition: s1 + scalar * s2_signed ≡ 0 (mod order)
    
    Args:
        scalar: The secret scalar
        s1: First component (u128, always positive)
        s2_encoded: Encoded s2 (sign-magnitude: if >= 2^128, negative)
    
    Returns:
        True if decomposition is valid
    """
    # Decode s2_encoded
    if s2_encoded >= (1 << 128):
        # Negative: s2_encoded = 2^128 + s2_abs
        s2_abs = s2_encoded - (1 << 128)
        s2_signed = -s2_abs
    else:
        # Positive: s2_encoded = s2_abs
        s2_abs = s2_encoded
        s2_signed = s2_abs
    
    # Verify: s1 + scalar * s2_signed ≡ 0 (mod order)
    check = (s1 + scalar * s2_signed) % ORDER
    
    print(f"Verification:")
    print(f"  Scalar: 0x{scalar:064x}")
    print(f"  s1: 0x{s1:032x}")
    print(f"  s2_encoded: 0x{s2_encoded:032x}")
    print(f"  s2_abs: {s2_abs}")
    print(f"  s2_signed: {s2_signed}")
    print(f"  (s1 + scalar * s2_signed) mod order = {check}")
    
    if check == 0:
        print(f"  ✅ Decomposition valid!")
        return True
    else:
        print(f"  ❌ Decomposition invalid!")
        return False

if __name__ == "__main__":
    # Load hint
    hint_path = Path(__file__).parent.parent / "cairo" / "adaptor_point_hint.json"
    
    with open(hint_path, 'r') as f:
        hint_data = json.load(f)
    
    hint = hint_data['adaptor_point_hint']
    scalar_hex = hint_data['scalar']
    scalar = int(scalar_hex, 16)
    
    # Extract s1 and s2_encoded (indices 8 and 9)
    s1 = hint[8]
    s2_encoded = hint[9]
    
    print("=" * 80)
    print("Verifying fake-GLV decomposition")
    print("=" * 80)
    print()
    
    is_valid = verify_decomposition(scalar, s1, s2_encoded)
    
    if not is_valid:
        print("\n❌ Current hint has invalid decomposition!")
        print("   Need to regenerate using correct algorithm.")
        exit(1)
    else:
        print("\n✅ Current hint is valid!")

