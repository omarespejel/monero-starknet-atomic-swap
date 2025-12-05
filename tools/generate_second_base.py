#!/usr/bin/env python3
"""
Generate the second Ed25519 generator point Y for DLEQ proofs.

Computes Y = hash_to_curve("DLEQ_SECOND_BASE_V1") and outputs Cairo-formatted u384 limbs.
This matches the Rust implementation in rust/src/dleq.rs::get_second_generator().

Usage:
    python3 tools/generate_second_base.py

Output:
    Cairo code snippet with hardcoded G1Point constant for get_dleq_second_generator().
"""

import hashlib
import sys
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from curve25519_dalek.constants import ED25519_BASEPOINT_POINT
    from curve25519_dalek.edwards import EdwardsPoint
    from curve25519_dalek.scalar import Scalar
except ImportError:
    print("Error: curve25519_dalek not installed. Install with: pip install curve25519-dalek")
    sys.exit(1)


def hash_to_edwards_point(domain_separator: bytes) -> EdwardsPoint:
    """
    Hash-to-curve for Ed25519 using SHA-512.
    
    Matches Rust implementation:
    ```rust
    let mut hasher = Sha512::new();
    hasher.update(b"DLEQ_SECOND_BASE_V1");
    EdwardsPoint::hash_from_bytes::<Sha512>(&hasher.finalize())
    ```
    """
    hasher = hashlib.sha512()
    hasher.update(domain_separator)
    hash_bytes = hasher.digest()
    
    # Use hash as scalar seed (first 32 bytes)
    scalar_bytes = hash_bytes[:32]
    scalar = Scalar.from_bytes_mod_order(scalar_bytes)
    
    # Compute Y = scalar * G
    Y_edwards = ED25519_BASEPOINT_POINT * scalar
    
    return Y_edwards


def split_to_limbs(value: int, bits_per_limb: int, num_limbs: int) -> list[int]:
    """
    Split integer into limbs of specified bit width.
    
    Args:
        value: Integer to split
        bits_per_limb: Number of bits per limb (e.g., 96 for u96)
        num_limbs: Number of limbs to generate
    
    Returns:
        List of limb values (little-endian: limb0, limb1, limb2, limb3)
    """
    mask = (1 << bits_per_limb) - 1
    limbs = []
    remaining = value
    
    for _ in range(num_limbs):
        limbs.append(remaining & mask)
        remaining >>= bits_per_limb
    
    return limbs


def edwards_to_weierstrass(edwards_point: EdwardsPoint) -> tuple[int, int]:
    """
    Convert Ed25519 Edwards point to Weierstrass coordinates.
    
    Note: This is a placeholder. In production, you need to implement the actual
    birational map from Edwards to Weierstrass form for curve_index=4 in Garaga.
    
    For now, this function is a stub that needs proper implementation.
    """
    # TODO: Implement proper Edwards → Weierstrass conversion
    # This requires:
    # 1. Extract (x, y) from EdwardsPoint
    # 2. Apply birational map: (u, v) = f(x, y)
    # 3. Return (u, v) as integers
    
    # Placeholder: return zeros (will need actual conversion)
    print("WARNING: Edwards → Weierstrass conversion not yet implemented!")
    print("This tool needs the actual conversion logic from your Python toolchain.")
    return (0, 0)


def generate_second_base():
    """Generate second Ed25519 generator Y and output Cairo code."""
    
    # Hash-to-curve (must match Rust implementation exactly)
    domain_separator = b"DLEQ_SECOND_BASE_V1"
    Y_edwards = hash_to_edwards_point(domain_separator)
    
    print(f"// Generated second generator Y = hash_to_curve('DLEQ_SECOND_BASE_V1')")
    print(f"// Edwards point (compressed): {Y_edwards.compress().to_bytes().hex()}")
    print()
    
    # Convert to Weierstrass (for Garaga curve_index=4)
    # TODO: Implement actual conversion
    u, v = edwards_to_weierstrass(Y_edwards)
    
    if u == 0 and v == 0:
        print("// ERROR: Conversion not implemented. Using placeholder.")
        print("// TODO: Implement Edwards → Weierstrass conversion")
        return
    
    # Split into u384 limbs (96 bits each, 4 limbs)
    u_limbs = split_to_limbs(u, 96, 4)
    v_limbs = split_to_limbs(v, 96, 4)
    
    # Generate Cairo code
    print("fn get_dleq_second_generator() -> G1Point {")
    print("    G1Point {")
    print("        x: u384 {")
    print(f"            limb0: 0x{u_limbs[0]:024x},")
    print(f"            limb1: 0x{u_limbs[1]:024x},")
    print(f"            limb2: 0x{u_limbs[2]:024x},")
    print(f"            limb3: 0x{u_limbs[3]:024x}")
    print("        },")
    print("        y: u384 {")
    print(f"            limb0: 0x{v_limbs[0]:024x},")
    print(f"            limb1: 0x{v_limbs[1]:024x},")
    print(f"            limb2: 0x{v_limbs[2]:024x},")
    print(f"            limb3: 0x{v_limbs[3]:024x}")
    print("        }")
    print("    }")
    print("}")


if __name__ == "__main__":
    try:
        generate_second_base()
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)

