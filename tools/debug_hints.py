#!/usr/bin/env python3
"""
Debug sqrt hints to verify they match Garaga's validation requirements.

This script checks:
1. sqrt_hint^2 == (y^2 - 1) / (d*y^2 + 1) mod p
2. sqrt_hint parity vs sign_bit parity
3. sqrt_hint range (< Ed25519 prime)
4. What Garaga will do with the hint
"""

# Ed25519 field prime
P = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed

# Ed25519 twisted Edwards curve parameter d
D = 0x52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3


def debug_hint(compressed_hex: str, sqrt_hint_low: str, sqrt_hint_high: str):
    """
    Debug a sqrt hint for a compressed Ed25519 point.
    
    Args:
        compressed_hex: Hex string of compressed point (32 bytes)
        sqrt_hint_low: Hex string of sqrt hint low u128
        sqrt_hint_high: Hex string of sqrt hint high u128
    """
    # Parse compressed point
    # Ed25519 compressed format: 32 bytes = 31 bytes (y-coordinate) + 1 byte (sign bit)
    compressed_bytes = bytes.fromhex(compressed_hex.replace('0x', ''))
    compressed = int.from_bytes(compressed_bytes, 'little')
    
    # Extract sign bit (bit 255) and y-coordinate (bits 0-254)
    sign_bit = (compressed >> 255) & 1
    y = compressed & ((1 << 255) - 1)
    
    # Parse sqrt hint (reconstruct from low/high)
    hint_low = int(sqrt_hint_low.replace('0x', ''), 16)
    hint_high = int(sqrt_hint_high.replace('0x', ''), 16)
    sqrt_hint = hint_low + (hint_high << 128)
    
    # Compute expected x_squared
    y_sq = (y * y) % P
    numerator = (y_sq - 1) % P
    denominator = (D * y_sq + 1) % P
    x_squared_expected = (numerator * pow(denominator, -1, P)) % P
    
    # Check if sqrt_hint^2 matches
    hint_squared = (sqrt_hint * sqrt_hint) % P
    
    # Check Garaga's parity logic
    hint_parity = sqrt_hint % 2
    
    print("=" * 80)
    print(f"Debugging sqrt hint for compressed point:")
    print("=" * 80)
    print(f"Compressed point: {compressed_hex}")
    print(f"  y-coordinate: 0x{y:064x}")
    print(f"  sign_bit: {sign_bit}")
    print(f"\nSqrt hint:")
    print(f"  low:  0x{hint_low:032x}")
    print(f"  high: 0x{hint_high:032x}")
    print(f"  full: 0x{sqrt_hint:064x}")
    print(f"  sqrt_hint % 2: {hint_parity}")
    print(f"  sign_bit % 2: {sign_bit % 2}")
    print(f"  Parities match: {hint_parity == (sign_bit % 2)}")
    
    print(f"\nValidation:")
    print(f"  x_squared expected: 0x{x_squared_expected:064x}")
    print(f"  hint^2:            0x{hint_squared:064x}")
    print(f"  Match: {hint_squared == x_squared_expected}")
    
    # Range check
    if sqrt_hint >= P:
        print(f"\n❌ ERROR: sqrt_hint >= Ed25519 prime!")
        print(f"  sqrt_hint: 0x{sqrt_hint:064x}")
        print(f"  P:         0x{P:064x}")
    else:
        print(f"\n✓ Range check: sqrt_hint < P")
    
    # If parities don't match, Garaga will negate
    if hint_parity != (sign_bit % 2):
        negated = (-sqrt_hint) % P
        negated_squared = (negated * negated) % P
        print(f"\nAfter Garaga negates (parities don't match):")
        print(f"  negated hint: 0x{negated:064x}")
        print(f"  negated^2:    0x{negated_squared:064x}")
        print(f"  Match: {negated_squared == x_squared_expected}")
        
        if negated_squared == x_squared_expected:
            print(f"\n✅ SUCCESS: After negation, hint is correct!")
        else:
            print(f"\n❌ FAILURE: Even after negation, hint^2 doesn't match!")
    else:
        if hint_squared == x_squared_expected:
            print(f"\n✅ SUCCESS: Hint is correct (no negation needed)!")
        else:
            print(f"\n❌ FAILURE: Hint^2 doesn't match expected x_squared!")
    
    print()


def main():
    """Debug all points from test files."""
    import json
    from pathlib import Path
    
    test_vectors_path = Path(__file__).parent.parent / "rust" / "test_vectors.json"
    
    if not test_vectors_path.exists():
        print(f"Error: {test_vectors_path} not found")
        return
    
    with open(test_vectors_path, 'r') as f:
        vectors = json.load(f)
    
    points = [
        ("adaptor_point", vectors["adaptor_point_compressed"], 
         vectors["adaptor_point_sqrt_hint_u256"]["low"],
         vectors["adaptor_point_sqrt_hint_u256"]["high"]),
        ("second_point", vectors["second_point_compressed"],
         vectors["second_point_sqrt_hint_u256"]["low"],
         vectors["second_point_sqrt_hint_u256"]["high"]),
        ("r1", vectors["r1_compressed"],
         vectors["r1_sqrt_hint_u256"]["low"],
         vectors["r1_sqrt_hint_u256"]["high"]),
        ("r2", vectors["g_compressed"],  # R2 uses Ed25519 base point
         "0x9f3ee81fe68dcbcf9de661eedd114a9e",
         "0x397c8b3280ddfb2ffe72518d79cc504c"),
    ]
    
    for name, compressed, hint_low, hint_high in points:
        debug_hint(compressed, hint_low, hint_high)


if __name__ == "__main__":
    main()

