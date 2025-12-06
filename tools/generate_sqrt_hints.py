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
    
    # Compute x = sqrt(x_sq)
    # For Ed25519, sqrt is computed as x = x_sq^((p+3)/8)  mod p
    x = pow(x_sq, (P + 3) // 8, P)
    
    # If x^2 != x_sq, multiply by sqrt(-1) = 2^((p-1)/4)
    if (x * x) % P != x_sq:
        # sqrt(-1) for Ed25519
        I = pow(2, (P - 1) // 4, P)
        x = (x * I) % P
    
    # Verify that x^2 = x_sq
    assert (x * x) % P == x_sq, f"Square root verification failed: {hex(x)}^2 != {hex(x_sq)}"
    
    # Adjust sign: if sign bit doesn't match x parity, negate x
    if (x & 1) != sign_bit:
        x = P - x
    
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
    # Load existing test vectors
    with open("ed25519_test_data.json", "r") as f:
        test_vectors = json.load(f)
    
    updated_vectors = []
    
    for i, vec in enumerate(test_vectors):
        print(f"\nProcessing vector {i}...")
        
        # Get compressed point from vector
        compressed_hex = vec["compressed_edwards"]
        compressed_int = int(compressed_hex, 16)
        
        print(f"  Compressed point: {compressed_hex}")
        
        # Recover x-coordinate on twisted Edwards curve
        x_twisted = xrecover_twisted_edwards(compressed_int)
        
        print(f"  Recovered x_twisted: 0x{x_twisted:064x}")
        
        # Convert to u256 format
        sqrt_hint_u256 = int_to_u256(x_twisted)
        
        print(f"  sqrt_hint.low:  0x{sqrt_hint_u256['low']:032x}")
        print(f"  sqrt_hint.high: 0x{sqrt_hint_u256['high']:032x}")
        
        # Update vector with correct sqrt hint
        vec["sqrt_hint"] = sqrt_hint_u256
        updated_vectors.append(vec)
    
    # Write updated vectors
    with open("ed25519_test_data.json", "w") as f:
        json.dump(updated_vectors, f, indent=2)
    
    print("\n✅ Updated ed25519_test_data.json with correct sqrt hints!")
    print("\nThe sqrt hints are now x-coordinates on the TWISTED EDWARDS curve,")
    print("matching Garaga's exact decompression pattern.")


if __name__ == "__main__":
    main()
