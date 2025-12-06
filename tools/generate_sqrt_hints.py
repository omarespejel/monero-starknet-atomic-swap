#!/usr/bin/env python3
"""
Generate correct sqrt hints for Ed25519 compressed point decompression.

Based on Garaga's exact pattern from:
https://github.com/keep-starknet-strange/garaga/blob/main/hydra/garaga/starknet/tests_and_calldata_generators/signatures.py

The sqrt hint is the x-coordinate in TWISTED EDWARDS form, not Weierstrass form.
"""

import json
import sys


# Ed25519 field prime
P = 0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffed

# Ed25519 twisted Edwards curve parameters
# -x^2 + y^2 = 1 + d*x^2*y^2
A = -1  # coefficient for x^2
D = 0x52036cee2b6ffe738cc740797779e89800700a4d4141d8ab75eb4dca135978a3


def xrecover_twisted_edwards(y_compressed: int) -> int:
    """
    Recover x-coordinate on twisted Edwards curve from compressed y.
    This follows RFC 8032 Section 5.1.3 exactly.
    
    Args:
        y_compressed: Compressed point (y | sign_bit << 255)
    
    Returns:
        x-coordinate on twisted Edwards curve
    """
    # Extract sign bit and y-coordinate
    sign_bit = (y_compressed >> 255) & 1
    y = y_compressed & ((1 << 255) - 1)
    
    # Compute x^2 = (y^2 - 1) / (d*y^2 + 1)  mod p
    y_sq = (y * y) % P
    numerator = (y_sq - 1) % P
    denominator = (D * y_sq + 1) % P
    
    # Compute x^2
    x_sq = (numerator * pow(denominator, -1, P)) % P
    
    # Compute x = sqrt(x_sq) using RFC 8032 method
    # x = x_sq^((p+3)/8) mod p
    x = pow(x_sq, (P + 3) // 8, P)
    
    # Check if x^2 = x_sq or x^2 = -x_sq
    x_sq_check = (x * x) % P
    if x_sq_check == x_sq:
        # x is correct
        pass
    elif x_sq_check == (P - x_sq) % P:
        # Need to multiply by sqrt(-1)
        # sqrt(-1) mod p = 2^((p-1)/4) mod p
        I = pow(2, (P - 1) // 4, P)
        x = (x * I) % P
        # Verify after multiplication
        assert (x * x) % P == x_sq, f"Square root failed after I multiplication"
    else:
        # This shouldn't happen for valid Ed25519 points
        raise ValueError(f"Invalid square root: x^2 = {hex(x_sq_check)}, expected {hex(x_sq)} or {hex((P - x_sq) % P)}")
    
    # Adjust sign: if sign bit doesn't match x parity, negate x
    if (x & 1) != sign_bit:
        x = (P - x) % P
    
    return x


def split_128(value: int) -> tuple[int, int]:
    """
    Split a u256 into two u128 limbs (little-endian).
    Matches Garaga's split_128 pattern.
    
    Args:
        value: u256 integer
    
    Returns:
        (low_u128, high_u128) tuple
    """
    low = value & ((1 << 128) - 1)
    high = (value >> 128) & ((1 << 128) - 1)
    return (low, high)


def int_to_u256(value: int) -> dict:
    """
    Convert integer to Garaga's u256 format.
    
    Args:
        value: Integer to convert
    
    Returns:
        Dictionary with 'low' and 'high' u128 limbs
    """
    low, high = split_128(value)
    return {"low": low, "high": high}


def main():
    import os
    from pathlib import Path
    
    # Load test vectors from rust/test_vectors.json
    test_vectors_path = Path(__file__).parent.parent / "rust" / "test_vectors.json"
    
    if not test_vectors_path.exists():
        print(f"Error: {test_vectors_path} not found")
        sys.exit(1)
    
    with open(test_vectors_path, "r") as f:
        test_vector = json.load(f)
    
    print("=" * 80)
    print("Generating Correct Sqrt Hints for Ed25519 Compressed Points")
    print("=" * 80)
    print()
    print("Root Cause: sqrt_hint must be x-coordinate on TWISTED EDWARDS curve")
    print("(not Weierstrass x-coordinate)")
    print()
    
    # Points to process
    points = {
        "adaptor_point": test_vector["adaptor_point_compressed"],
        "second_point": test_vector["second_point_compressed"],
        "r1": test_vector["r1_compressed"],
        "r2": test_vector["r2_compressed"],
    }
    
    updated_hints = {}
    
    for point_name, compressed_hex in points.items():
        print(f"Processing {point_name}...")
        
        # Remove 0x prefix if present
        compressed_hex = compressed_hex.replace("0x", "")
        compressed_int = int(compressed_hex, 16)
        
        print(f"  Compressed: {compressed_hex}")
        
        # Recover x-coordinate on twisted Edwards curve
        x_twisted = xrecover_twisted_edwards(compressed_int)
        
        print(f"  x_twisted: 0x{x_twisted:064x}")
        
        # Convert to u256 format
        sqrt_hint_u256 = int_to_u256(x_twisted)
        
        print(f"  sqrt_hint.low:  0x{sqrt_hint_u256['low']:032x}")
        print(f"  sqrt_hint.high: 0x{sqrt_hint_u256['high']:032x}")
        print()
        
        updated_hints[f"{point_name}_sqrt_hint"] = sqrt_hint_u256
    
    # Update test vector
    for key, hint in updated_hints.items():
        # Convert to hex string format (for compatibility)
        hint_hex = f"0x{hint['low']:032x}{hint['high']:032x}"
        test_vector[key.replace("_sqrt_hint", "_sqrt_hint")] = hint_hex
        
        # Also store as u256 dict for Cairo
        test_vector[f"{key}_u256"] = hint
    
    # Write updated test vectors
    with open(test_vectors_path, "w") as f:
        json.dump(test_vector, f, indent=2)
    
    print("=" * 80)
    print("✅ Updated test_vectors.json with correct sqrt hints!")
    print()
    print("Cairo u256 format:")
    for point_name in ["adaptor_point", "second_point", "r1", "r2"]:
        hint = updated_hints[f"{point_name}_sqrt_hint"]
        print(f"  {point_name.upper()}_SQRT_HINT: u256 {{")
        print(f"    low: 0x{hint['low']:x},")
        print(f"    high: 0x{hint['high']:x},")
        print(f"  }}")
    print()
    print("The sqrt hints are now x-coordinates on the TWISTED EDWARDS curve,")
    print("matching Garaga's exact decompression pattern.")


if __name__ == "__main__":
    main()
