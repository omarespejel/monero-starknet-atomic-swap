#!/usr/bin/env python3
"""
Generate correct sqrt hints using Garaga's exact algorithm.

This fixes the issue where Rust generates Montgomery coordinates but Garaga
expects twisted Edwards coordinates for sqrt hints.
"""

import json
import sys
from pathlib import Path

# Add parent directory to path
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from garaga.curves import CurveID, CURVES
    from garaga.signatures.eddsa_25519 import decompress_edwards_pt_from_y_compressed_le_into_weirstrasspoint
except ImportError:
    print("ERROR: garaga package not found.")
    print("Install with: source tools/.venv/bin/activate && pip install garaga==1.0.1")
    sys.exit(1)


def hex_to_u256(hex_str: str) -> tuple[int, int]:
    """Convert 32-byte hex string to u256 (low, high)."""
    hex_str = hex_str.replace('0x', '').replace(' ', '')
    if len(hex_str) != 64:
        raise ValueError(f"Hex string must be 64 characters, got {len(hex_str)}")
    
    bytes_val = bytes.fromhex(hex_str)
    low = int.from_bytes(bytes_val[:16], 'little')
    high = int.from_bytes(bytes_val[16:], 'little')
    return (low, high)


def get_correct_sqrt_hint(compressed_hex: str) -> tuple[int, int]:
    """
    Generate correct sqrt hint using Garaga's exact algorithm.
    
    The sqrt hint must satisfy:
    sqrt_hint² ≡ (y² - 1) / (d·y² + 1) mod p
    
    Where d is Ed25519's twisted Edwards coefficient.
    """
    curve = CURVES[CurveID.ED25519.value]
    p = curve.p
    d = curve.d_twisted  # Ed25519 twisted d
    
    # Parse compressed point (little-endian)
    compressed_bytes = bytes.fromhex(compressed_hex)
    compressed_int = int.from_bytes(compressed_bytes, 'little')
    
    # Extract sign bit and y-coordinate
    sign_bit = (compressed_int >> 255) & 1
    y = compressed_int & ((1 << 255) - 1)
    
    # Compute x² = (y² - 1) / (d*y² + 1) mod p
    y2 = (y * y) % p
    numerator = (y2 - 1) % p
    denominator = (d * y2 + 1) % p
    
    # Modular inverse
    inv_denominator = pow(denominator, -1, p)
    x2 = (numerator * inv_denominator) % p
    
    # Compute x = sqrt(x²) mod p using Tonelli-Shanks or (p+3)/8 method
    # For Ed25519, p ≡ 5 (mod 8), so we can use (p+3)/8
    x = pow(x2, (p + 3) // 8, p)
    
    # Verify x² ≡ x2 (mod p), if not adjust
    if (x * x) % p != x2:
        # Try p - x
        x = p - x
        if (x * x) % p != x2:
            raise ValueError(f"Could not compute sqrt of {hex(x2)} mod p")
    
    # Adjust for sign bit
    if (x & 1) != sign_bit:
        x = p - x
    
    # Convert to u256 {low, high} (little-endian)
    low = x & ((1 << 128) - 1)
    high = x >> 128
    
    return low, high


def main():
    """Generate sqrt hints for all points in test_vectors.json."""
    script_dir = Path(__file__).parent
    test_vectors_path = script_dir.parent / "rust" / "test_vectors.json"
    
    if not test_vectors_path.exists():
        print(f"Error: {test_vectors_path} not found")
        sys.exit(1)
    
    with open(test_vectors_path, 'r') as f:
        tv = json.load(f)
    
    print("=" * 80)
    print("GENERATING CORRECT SQRT HINTS USING GARAGA'S ALGORITHM")
    print("=" * 80)
    print()
    
    # Generate hints for all points
    points = {
        'Adaptor Point (T)': tv['adaptor_point_compressed'],
        'Second Point (U)': tv['second_point_compressed'],
        'R1': tv['r1_compressed'],
        'R2': tv['r2_compressed'],
    }
    
    results = {}
    for name, compressed_hex in points.items():
        try:
            low, high = get_correct_sqrt_hint(compressed_hex)
            results[name] = {
                'compressed': compressed_hex,
                'low': low,
                'high': high,
                'cairo_format': f"u256 {{ low: 0x{low:032x}, high: 0x{high:032x} }}"
            }
            print(f"✅ {name}:")
            print(f"   Compressed: {compressed_hex}")
            print(f"   Cairo: {results[name]['cairo_format']}")
            print()
        except Exception as e:
            print(f"❌ {name}: Error - {e}")
            print()
    
    print("=" * 80)
    print("CAIRO CONSTANTS FOR test_e2e_dleq.cairo")
    print("=" * 80)
    print()
    print("// Sqrt hints generated using Garaga's exact algorithm")
    print(f"const TEST_ADAPTOR_POINT_SQRT_HINT: u256 = {results['Adaptor Point (T)']['cairo_format']};")
    print(f"const TEST_SECOND_POINT_SQRT_HINT: u256 = {results['Second Point (U)']['cairo_format']};")
    print(f"const TEST_R1_SQRT_HINT: u256 = {results['R1']['cairo_format']};")
    print(f"const TEST_R2_SQRT_HINT: u256 = {results['R2']['cairo_format']};")
    print()
    
    # Save to JSON for reference
    output_path = script_dir.parent / "cairo" / "correct_sqrt_hints.json"
    with open(output_path, 'w') as f:
        json.dump(results, f, indent=2)
    print(f"✅ Saved to {output_path}")


if __name__ == "__main__":
    main()

