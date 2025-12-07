#!/usr/bin/env python3
"""Convert hex strings to Cairo u256 { low, high } format.

This script prevents byte-order bugs when converting Rust hex constants
to Cairo u256 format. Always use this script when adding new constants
from test_vectors.json or Rust code.

Usage:
    python3 tools/hex_to_cairo_u256.py <64-char-hex>

Example:
    python3 tools/hex_to_cairo_u256.py c9a3f86aae465f0e56513864510f3997561fa2c9e85ea21dc2292309f3cd6022
"""

import sys


def hex_to_cairo_u256(hex_str: str) -> str:
    """Convert a 64-character hex string to Cairo u256 format.
    
    Args:
        hex_str: 64-character hex string (32 bytes)
        
    Returns:
        Cairo u256 format string: u256 { low: 0x..., high: 0x... }
    """
    # Remove any whitespace or 0x prefix
    hex_str = hex_str.strip().replace('0x', '').replace(' ', '')
    
    if len(hex_str) != 64:
        raise ValueError(f"Hex string must be exactly 64 characters (32 bytes), got {len(hex_str)}")
    
    b = bytes.fromhex(hex_str)
    low = int.from_bytes(b[0:16], 'little')
    high = int.from_bytes(b[16:32], 'little')
    
    return f"u256 {{ low: 0x{low:032x}, high: 0x{high:032x} }}"


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python3 tools/hex_to_cairo_u256.py <64-char-hex>")
        print("\nExample:")
        print("  python3 tools/hex_to_cairo_u256.py c9a3f86aae465f0e56513864510f3997561fa2c9e85ea21dc2292309f3cd6022")
        sys.exit(1)
    
    try:
        result = hex_to_cairo_u256(sys.argv[1])
        print(result)
    except ValueError as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)

