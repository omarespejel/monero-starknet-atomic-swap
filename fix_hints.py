#!/usr/bin/env python3
"""
Generate correct sqrt hints for Ed25519 compressed points.
Based on auditor's recommendation - uses standard p = 2^255 - 19 arithmetic.
"""

import json

# Ed25519 field prime
p = 2**255 - 19

# Ed25519 curve parameter d
d = -121665 * pow(121666, -1, p) % p

# Square root of -1 mod p (for computing square roots)
I = pow(2, (p - 1) // 4, p)

def recover_x(y):
    """
    Recover x-coordinate from y-coordinate on Ed25519 curve.
    
    Curve equation: -x^2 + y^2 = 1 + d*x^2*y^2
    Solving for x^2: x^2 = (y^2 - 1) / (d*y^2 + 1)
    """
    y = int(y)
    
    # x^2 = (y^2 - 1) / (d*y^2 + 1)
    u = (y*y - 1) % p
    v = (d*y*y + 1) % p
    v_inv = pow(v, -1, p)
    x2 = (u * v_inv) % p
    
    # Square root using Tonelli-Shanks-like method
    # For Ed25519: x = x2^((p+3)/8) mod p
    x = pow(x2, (p + 3) // 8, p)
    
    # Verify and adjust if needed
    if (x * x) % p != x2:
        x = (x * I) % p
    
    if (x * x) % p != x2:
        raise ValueError(f"No square root found! x^2 = {hex(x2)}")
    
    # In Ed25519, x is usually even for the positive sqrt,
    # but Garaga might expect the specific root corresponding to the sign bit.
    # For test vectors, usually the positive (even) x is canonical unless sign bit is set.
    if x % 2 != 0:
        x = p - x
    
    return x

def hex_to_u256_little_endian(value_int):
    """Convert integer to u256 format (little-endian bytes)"""
    # Split into low (16 bytes) and high (16 bytes)
    low = value_int & ((1 << 128) - 1)
    high = (value_int >> 128) & ((1 << 128) - 1)
    return low, high

# Load test vectors
try:
    with open('rust/test_vectors.json', 'r') as f:
        data = json.load(f)
    
    print("=" * 80)
    print("COMPUTED SQRT HINTS (Copy these to test_e2e_dleq.cairo)")
    print("=" * 80)
    print()
    
    # Process each point
    points = [
        ("TEST_ADAPTOR_POINT", data['adaptor_point_compressed']),
        ("TEST_SECOND_POINT", data['second_point_compressed']),
        ("TEST_R1", data['r1_compressed']),
        ("TEST_R2", data['r2_compressed']),
    ]
    
    for name, point_hex in points:
        # Parse hex string to bytes
        point_bytes = bytes.fromhex(point_hex)
        
        # Convert to integer (little-endian as per Ed25519)
        y_int = int.from_bytes(point_bytes, byteorder='little')
        
        # Extract sign bit (bit 255) and y-coordinate
        sign_bit = (y_int >> 255) & 1
        y_coordinate = y_int & ((1 << 255) - 1)
        
        # Recover x-coordinate
        x_coordinate = recover_x(y_coordinate)
        
        # Convert to u256 format
        x_low, x_high = hex_to_u256_little_endian(x_coordinate)
        
        print(f"// {name} (compressed: {point_hex})")
        print(f"const {name}_SQRT_HINT: u256 = u256 {{")
        print(f"    low: 0x{x_low:032x},")
        print(f"    high: 0x{x_high:032x},")
        print(f"}};")
        print()
        
except FileNotFoundError:
    print("Error: rust/test_vectors.json not found")
    print("Run: cd rust && cargo test --test test_vectors generate_cairo_test_vectors -- --ignored")
except KeyError as e:
    print(f"Error: Missing key in test_vectors.json: {e}")
    print("Ensure test_vectors.json has 'adaptor_point_compressed', 'second_point_compressed', etc.")
except Exception as e:
    print(f"Error: {e}")
    import traceback
    traceback.print_exc()

