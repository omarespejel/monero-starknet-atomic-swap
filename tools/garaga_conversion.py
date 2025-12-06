#!/usr/bin/env python3
"""
Garaga-style compressed Edwards point to u256 conversion utility.

This module provides functions to convert compressed Edwards points
from hex strings to Cairo u256 format, matching Garaga's exact pattern.
"""

def bytes_to_u256_garaga_style(bytes_32: bytes) -> dict:
    """
    Convert 32-byte compressed Edwards point to u256 using Garaga's pattern.
    
    CRITICAL: Compressed Edwards points are little-endian (RFC 8032)
    u256 { low, high } must match this byte order.
    
    Garaga pattern from io.py:
    - bytes[0..15]  → low  (u128, little-endian)
    - bytes[16..31] → high (u128, little-endian)
    
    Args:
        bytes_32: 32-byte compressed Edwards point (little-endian, RFC 8032)
    
    Returns:
        Dictionary with conversion results:
        - int: Integer value (little-endian interpretation)
        - hex: Hex string representation
        - cairo_u256: Cairo u256 literal format
        - low: Low u128 limb (hex)
        - high: High u128 limb (hex)
    """
    # Convert bytes to integer (little-endian, RFC 8032 standard)
    int_value = int.from_bytes(bytes_32, byteorder='little')
    
    # Split using Garaga's bigint_split pattern
    # For u256: 2 limbs of base 2^128
    low = int_value & ((1 << 128) - 1)   # Lower 128 bits
    high = (int_value >> 128) & ((1 << 128) - 1)  # Upper 128 bits
    
    return {
        "int": int_value,
        "hex": f"0x{int_value:064x}",
        "cairo_u256": f"u256 {{ low: 0x{low:x}, high: 0x{high:x} }}",
        "low": hex(low),
        "high": hex(high),
        "low_decimal": low,
        "high_decimal": high,
    }

def hex_string_to_u256_garaga_style(hex_string: str) -> dict:
    """
    Convert hex string (compressed Edwards point) to u256 using Garaga's pattern.
    
    Args:
        hex_string: Hex string (with or without 0x prefix)
    
    Returns:
        Dictionary with conversion results (same format as bytes_to_u256_garaga_style)
    """
    # Remove 0x prefix if present
    hex_string = hex_string.replace('0x', '')
    
    # Convert hex string to bytes
    bytes_32 = bytes.fromhex(hex_string)
    
    if len(bytes_32) != 32:
        raise ValueError(f"Expected 32 bytes, got {len(bytes_32)}")
    
    return bytes_to_u256_garaga_style(bytes_32)

def verify_test_vector_conversion(test_vector_hex: str, expected_low: int, expected_high: int) -> bool:
    """
    Verify that a test vector hex string converts correctly.
    
    Args:
        test_vector_hex: Hex string from test_vectors.json
        expected_low: Expected low u128 value (from Cairo test)
        expected_high: Expected high u128 value (from Cairo test)
    
    Returns:
        True if conversion matches expected values
    """
    result = hex_string_to_u256_garaga_style(test_vector_hex)
    
    matches = (
        result["low_decimal"] == expected_low and
        result["high_decimal"] == expected_high
    )
    
    if not matches:
        print(f"Mismatch for {test_vector_hex}:")
        print(f"  Expected: low=0x{expected_low:x}, high=0x{expected_high:x}")
        print(f"  Got:      low=0x{result['low_decimal']:x}, high=0x{result['high_decimal']:x}")
    
    return matches

if __name__ == "__main__":
    import sys
    import json
    
    if len(sys.argv) > 1:
        # Convert single hex string
        hex_str = sys.argv[1]
        result = hex_string_to_u256_garaga_style(hex_str)
        print(json.dumps(result, indent=2))
    else:
        # Verify all test vectors
        test_vectors_path = "../rust/test_vectors.json"
        with open(test_vectors_path) as f:
            test_vector = json.load(f)
        
        # Expected values from test_e2e_dleq.cairo
        expected = {
            "adaptor_point_compressed": {
                "low": 0x54e86953e7cc99b545cfef03f63cce85,
                "high": 0x427dde0adb325f957d29ad71e4643882,
            },
            "second_point_compressed": {
                "low": 0xd893b3476bdf09770b7616f84c5c7bbe,
                "high": 0x5c79d0fa84d6440908e2e2065e60d1cd,
            },
            "r1_compressed": {
                "low": 0x9c289904f3df85b691d32a931f4d239,
                "high": 0xf7926242a14aef11d6c54224331717ae,
            },
            "r2_compressed": {
                "low": 0x2a8dcb3f7f2fdfac40805970f83a3577,
                "high": 0xde953c10ba21a6970b15ecdc1a8d404,
            },
        }
        
        print("Verifying test vector conversions...")
        print("=" * 80)
        
        all_match = True
        for key, expected_values in expected.items():
            hex_str = test_vector[key]
            matches = verify_test_vector_conversion(
                hex_str,
                expected_values["low"],
                expected_values["high"]
            )
            if matches:
                print(f"✅ {key}: CORRECT")
            else:
                print(f"❌ {key}: MISMATCH")
                all_match = False
        
        print("=" * 80)
        if all_match:
            print("✅ All conversions match expected values")
            sys.exit(0)
        else:
            print("❌ Some conversions do not match")
            sys.exit(1)

