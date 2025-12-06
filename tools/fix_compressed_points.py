#!/usr/bin/env python3
"""
Fix compressed point conversion from hex strings to u256.

The issue: Compressed Ed25519 points in test_vectors.json are hex strings
representing 32 bytes in LITTLE-ENDIAN format (per RFC 8032). When converting
to u256 for Cairo, we must interpret these bytes as little-endian.

This script correctly converts hex strings to u256 structures.
"""

import json
from pathlib import Path


def fix_compressed_point_to_u256(hex_str: str) -> dict:
    """
    Convert a hex string (representing little-endian bytes per RFC 8032) 
    to u256 struct formatted for Cairo.
    
    Args:
        hex_str: Hex string like "85ce3cf603efcf45..." (32 bytes)
        
    Returns:
        Dict with 'low' and 'high' as hex strings and Cairo u256 format
    """
    # Remove any 0x prefix
    hex_str = hex_str.replace('0x', '').strip()
    
    # Convert hex string to bytes
    # This gives us the bytes in the order they appear in the hex string
    point_bytes = bytes.fromhex(hex_str)
    
    if len(point_bytes) != 32:
        raise ValueError(f"Expected 32 bytes, got {len(point_bytes)}")
    
    # Ed25519 compressed points are stored as 32 bytes in LITTLE-ENDIAN format
    # per RFC 8032. Convert to integer using little-endian byte order.
    value_le = int.from_bytes(point_bytes, byteorder='little')
    
    # Split into u128 limbs (low = bits 0-127, high = bits 128-255)
    low = value_le & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    high = (value_le >> 128) & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    
    return {
        'low': f'0x{low:032x}',
        'high': f'0x{high:032x}',
        'low_decimal': hex(low),
        'high_decimal': hex(high),
        'cairo_format': f"u256 {{\n    low: 0x{low:032x},\n    high: 0x{high:032x},\n}}"
    }


def main():
    """Convert all compressed points in test_vectors.json."""
    test_vectors_path = Path(__file__).parent.parent / "rust" / "test_vectors.json"
    
    if not test_vectors_path.exists():
        print(f"Error: {test_vectors_path} not found")
        return
    
    with open(test_vectors_path, 'r') as f:
        vectors = json.load(f)
    
    print("=" * 80)
    print("Converting Compressed Points from Hex Strings to u256")
    print("=" * 80)
    print()
    print("Root Cause: Hex strings represent LITTLE-ENDIAN bytes per RFC 8032")
    print("We must use int.from_bytes(bytes, byteorder='little') to convert correctly.")
    print()
    
    # Points to convert
    points_to_convert = [
        'adaptor_point_compressed',
        'second_point_compressed',
        'r1_compressed',
        'r2_compressed',
        'g_compressed',
        'y_compressed',
    ]
    
    results = {}
    
    for point_name in points_to_convert:
        if point_name in vectors:
            hex_str = vectors[point_name]
            print(f"{point_name}:")
            print(f"  Original hex: {hex_str}")
            
            try:
                result = fix_compressed_point_to_u256(hex_str)
                results[point_name] = result
                
                print(f"  Cairo u256:")
                print(f"    {result['cairo_format']}")
                print()
            except Exception as e:
                print(f"  ERROR: {e}")
                print()
    
    print("=" * 80)
    print("Summary - Copy these values into your Cairo test files:")
    print("=" * 80)
    print()
    
    for point_name, result in results.items():
        const_name = point_name.upper().replace('_COMPRESSED', '')
        print(f"const TEST_{const_name}: u256 = {result['cairo_format']};")
        print()


if __name__ == "__main__":
    main()

