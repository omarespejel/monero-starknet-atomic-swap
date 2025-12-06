#!/usr/bin/env python3
"""
Regenerate sqrt hints using Garaga's exact algorithm.

Based on Garaga source code analysis:
- Sqrt hint IS the x-coordinate (not a separate hint value)
- Must satisfy: sqrt_hint^2 == (y^2 - 1) / (d*y^2 + 1) mod p
- Sign bit matching: sqrt_hint.low % 2 must match compressed point's MSB sign bit
- Range check: sqrt_hint < 0x7ffff...fed (Ed25519 prime)

This matches Garaga's circuit implementation in eddsa_25519.cairo.
"""

import json
import sys
from pathlib import Path

# Ed25519 parameters
P = 2**255 - 19  # Ed25519 prime
D = -121665 * pow(121666, -1, P) % P  # Edwards d coefficient

def sqrt_ed25519(n: int) -> int:
    """
    Compute square root in GF(p) for Ed25519.
    Matches Garaga's circuit implementation.
    
    Uses (p+3)/8 exponentiation and checks if result squared equals input.
    If not, multiplies by sqrt(-1) = 2^((p-1)/4).
    """
    # Ed25519 uses (p+3)/8 exponentiation
    root = pow(n, (P + 3) // 8, P)
    
    # Check if root^2 == n
    if (root * root) % P != n % P:
        # Multiply by sqrt(-1) = 2^((p-1)/4)
        sqrt_m1 = pow(2, (P - 1) // 4, P)
        root = (root * sqrt_m1) % P
    
    # Verify: root^2 should equal n mod p
    assert (root * root) % P == n % P, f"Square root verification failed: root^2 = {(root * root) % P}, expected {n % P}"
    
    return root

def decompress_ed25519_point(y_compressed_bytes: bytes) -> tuple[int, int]:
    """
    Decompress Ed25519 point matching Garaga's algorithm.
    
    Args:
        y_compressed_bytes: 32-byte compressed Edwards point (little-endian, RFC 8032)
    
    Returns:
        (x, y) tuple where x is the sqrt hint (x-coordinate)
    """
    # Extract y-coordinate and sign bit
    y_int = int.from_bytes(y_compressed_bytes, 'little')
    sign_bit = (y_int >> 255) & 1
    y = y_int & ((1 << 255) - 1)  # Clear sign bit
    
    # Compute x^2 from Edwards curve equation:
    # -x^2 + y^2 = 1 + d*x^2*y^2
    # Rearranging: x^2 = (y^2 - 1) / (d*y^2 + 1)
    y_sq = (y * y) % P
    numerator = (y_sq - 1) % P
    denominator = (D * y_sq + 1) % P
    x_sq = (numerator * pow(denominator, -1, P)) % P
    
    # Compute sqrt (this is the hint!)
    x = sqrt_ed25519(x_sq)
    
    # Apply sign bit: if x % 2 != sign_bit, negate
    # Garaga checks: sqrt_hint.low % 2 == bit_sign
    if (x % 2) != sign_bit:
        x = (P - x) % P
    
    # Verify sign bit matches
    assert (x % 2) == sign_bit, f"Sign bit mismatch: x % 2 = {x % 2}, sign_bit = {sign_bit}"
    
    return (x, y)

def int_to_u256(value: int) -> dict:
    """
    Convert integer to Cairo u256 format (little-endian).
    
    Format: u256 { low: bits[0..127], high: bits[128..255] }
    """
    low = value & ((1 << 128) - 1)
    high = (value >> 128) & ((1 << 128) - 1)
    return {
        'low': low,
        'high': high,
        'low_hex': hex(low),
        'high_hex': hex(high)
    }

def generate_sqrt_hint_u256(compressed_hex: str) -> dict:
    """
    Generate sqrt hint in Cairo u256 format using Garaga's exact algorithm.
    
    Args:
        compressed_hex: Hex string of compressed Edwards point (32 bytes)
    
    Returns:
        Dictionary with u256 format and verification info
    """
    compressed_hex = compressed_hex.replace('0x', '')
    compressed_bytes = bytes.fromhex(compressed_hex)
    
    if len(compressed_bytes) != 32:
        raise ValueError(f"Compressed point must be 32 bytes, got {len(compressed_bytes)}")
    
    x, y = decompress_ed25519_point(compressed_bytes)
    
    # Convert to u256 (little-endian)
    x_u256 = int_to_u256(x)
    
    # Verify range check (Garaga requirement)
    if x >= P:
        raise ValueError(f"Sqrt hint out of range: x = {hex(x)} >= P = {hex(P)}")
    
    # Verify x^2 matches expected value
    y_sq = (y * y) % P
    numerator = (y_sq - 1) % P
    denominator = (D * y_sq + 1) % P
    x_sq_expected = (numerator * pow(denominator, -1, P)) % P
    x_sq_actual = (x * x) % P
    
    assert x_sq_actual == x_sq_expected, f"x^2 verification failed: {hex(x_sq_actual)} != {hex(x_sq_expected)}"
    
    return {
        'low': x_u256['low'],
        'high': x_u256['high'],
        'low_hex': x_u256['low_hex'],
        'high_hex': x_u256['high_hex'],
        'x_full': hex(x),
        'y_full': hex(y),
        'x_sq_verified': x_sq_actual == x_sq_expected
    }

def main():
    """Regenerate all sqrt hints from test_vectors.json."""
    script_dir = Path(__file__).parent
    test_vectors_path = script_dir.parent / "rust" / "test_vectors.json"
    
    if not test_vectors_path.exists():
        print(f"Error: {test_vectors_path} not found")
        sys.exit(1)
    
    with open(test_vectors_path, 'r') as f:
        vectors = json.load(f)
    
    points = {
        'adaptor_point': vectors['adaptor_point_compressed'],
        'second_point': vectors['second_point_compressed'],
        'r1': vectors['r1_compressed'],
        'r2': vectors['r2_compressed']
    }
    
    print("=" * 80)
    print("Regenerating sqrt hints using Garaga's exact algorithm")
    print("=" * 80)
    print()
    
    results = {}
    
    for name, compressed_hex in points.items():
        print(f"Processing {name}...")
        print(f"  Compressed: {compressed_hex}")
        
        try:
            hint = generate_sqrt_hint_u256(compressed_hex)
            results[name] = hint
            
            print(f"  ✅ Sqrt hint generated:")
            print(f"     low:  {hint['low_hex']}")
            print(f"     high: {hint['high_hex']}")
            print(f"     x (full): {hint['x_full']}")
            print(f"     x^2 verified: {hint['x_sq_verified']}")
            print()
        except Exception as e:
            print(f"  ❌ Failed: {e}")
            print()
            sys.exit(1)
    
    # Update test_vectors.json
    print("Updating test_vectors.json...")
    for name, hint in results.items():
        key = f"{name}_sqrt_hint"
        # Format as 64-byte hex string (matching Rust format)
        # Format: [high (32 bytes)][low (32 bytes)] as hex
        high_bytes = hint['high'].to_bytes(16, 'little').hex()
        low_bytes = hint['low'].to_bytes(16, 'little').hex()
        vectors[key] = f"{high_bytes:0>64}{low_bytes:0>64}"
        
        # Also update u256 format
        vectors[f"{key}_u256"] = {
            "low": hint['low_hex'],
            "high": hint['high_hex']
        }
    
    # Write updated test_vectors.json
    with open(test_vectors_path, 'w') as f:
        json.dump(vectors, f, indent=2)
    
    print("✅ test_vectors.json updated successfully!")
    print()
    
    # Print Cairo constants
    print("=" * 80)
    print("Cairo u256 constants for test file:")
    print("=" * 80)
    print()
    
    for name, hint in results.items():
        const_name = name.upper().replace('_', '_')
        print(f"const TEST_{const_name}_SQRT_HINT: u256 = u256 {{")
        print(f"    low: {hint['low_hex']},")
        print(f"    high: {hint['high_hex']},")
        print(f"}};")
        print()

if __name__ == "__main__":
    main()

