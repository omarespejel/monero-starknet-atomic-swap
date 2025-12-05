#!/usr/bin/env python3
"""
Generate MSM hints for DLEQ verification scalars.

This tool generates fake-GLV hints for the scalars used in DLEQ verification:
- s (response scalar)
- c (challenge scalar)
- -c (negated challenge scalar)

These hints are required for Garaga's MSM operations to work correctly in production.
"""

import sys
from typing import Tuple, List

from garaga.curves import CurveID, CURVES
from garaga.points import G1Point
from garaga.hints.fake_glv import get_fake_glv_hint


def u384_to_cairo_tuple(value) -> Tuple[int, int, int, int]:
    """Convert u384 to Cairo tuple format (4×96-bit limbs)."""
    # u384 is stored as 4 u96 limbs
    # Each limb is 96 bits
    mask_96 = (1 << 96) - 1
    limb0 = value & mask_96
    limb1 = (value >> 96) & mask_96
    limb2 = (value >> 192) & mask_96
    limb3 = (value >> 288) & mask_96
    return (limb0, limb1, limb2, limb3)


def format_cairo_hint(hint_felts: List[int]) -> str:
    """Format hint as Cairo array literal."""
    felts_str = ", ".join([hex(f) for f in hint_felts])
    return f"array![{felts_str}].span()"


def generate_dleq_hints(
    s_scalar: int,
    c_scalar: int,
    curve_id: CurveID = CurveID.ED25519,
) -> dict:
    """
    Generate MSM hints for DLEQ verification scalars.
    
    Args:
        s_scalar: Response scalar s (from DLEQ proof)
        c_scalar: Challenge scalar c (from DLEQ proof)
        curve_id: Curve identifier (default: Ed25519)
    
    Returns:
        Dictionary with hints for s, c, and -c scalars
    """
    curve = CURVES[curve_id.value]
    
    # Reduce scalars modulo curve order
    s_scalar = s_scalar % curve.n
    c_scalar = c_scalar % curve.n
    
    # Compute -c mod n
    c_neg_scalar = (curve.n - c_scalar) % curve.n
    
    # Get generator
    generator = G1Point.get_nG(curve_id, 1)
    
    # Generate hints for each scalar
    def generate_hint_for_scalar(scalar: int) -> Tuple[List[int], G1Point]:
        """Generate fake-GLV hint for a scalar."""
        Q, s1, s2_encoded = get_fake_glv_hint(generator, scalar)
        
        # Convert Q to u384 limbs
        Q_x_limbs = u384_to_cairo_tuple(Q.x)
        Q_y_limbs = u384_to_cairo_tuple(Q.y)
        
        # Format as 10-felt hint: [Q.x limbs (4), Q.y limbs (4), s1, s2_encoded]
        hint_felts = [*Q_x_limbs, *Q_y_limbs, s1, s2_encoded]
        
        return hint_felts, Q
    
    # Generate hints
    s_hint_felts, s_hint_Q = generate_hint_for_scalar(s_scalar)
    c_hint_felts, c_hint_Q = generate_hint_for_scalar(c_scalar)
    c_neg_hint_felts, c_neg_hint_Q = generate_hint_for_scalar(c_neg_scalar)
    
    return {
        "s_scalar": {
            "value": s_scalar,
            "hint_felts": s_hint_felts,
            "cairo_hint": format_cairo_hint(s_hint_felts),
            "hint_Q": s_hint_Q,
        },
        "c_scalar": {
            "value": c_scalar,
            "hint_felts": c_hint_felts,
            "cairo_hint": format_cairo_hint(c_hint_felts),
            "hint_Q": c_hint_Q,
        },
        "c_neg_scalar": {
            "value": c_neg_scalar,
            "hint_felts": c_neg_hint_felts,
            "cairo_hint": format_cairo_hint(c_neg_hint_felts),
            "hint_Q": c_neg_hint_Q,
        },
        "curve_info": {
            "name": "ED25519",
            "curve_id": curve_id.value,
            "order": curve.n,
        },
    }


def print_hints(data: dict) -> None:
    """Print hints in human-readable format."""
    print("=" * 80)
    print("DLEQ MSM HINTS FOR CAIRO")
    print("=" * 80)
    print()
    
    print("## SCALAR s (Response)")
    print(f"Value:     {hex(data['s_scalar']['value'])}")
    print(f"Cairo hint: {data['s_scalar']['cairo_hint']}")
    print()
    
    print("## SCALAR c (Challenge)")
    print(f"Value:     {hex(data['c_scalar']['value'])}")
    print(f"Cairo hint: {data['c_scalar']['cairo_hint']}")
    print()
    
    print("## SCALAR -c (Negated Challenge)")
    print(f"Value:     {hex(data['c_neg_scalar']['value'])}")
    print(f"Cairo hint: {data['c_neg_scalar']['cairo_hint']}")
    print()
    
    print("## CAIRO SNIPPET")
    print("// Use these hints in _verify_dleq_proof:")
    print(f"let s_hint = {data['s_scalar']['cairo_hint']};")
    print(f"let c_neg_hint = {data['c_neg_scalar']['cairo_hint']};")
    print()
    print("=" * 80)


def main() -> None:
    """Main entry point."""
    if len(sys.argv) < 3:
        print("Usage: python generate_dleq_hints.py <s_scalar_hex> <c_scalar_hex>")
        print("Example: python generate_dleq_hints.py 0x1234... 0xabcd...")
        sys.exit(1)
    
    s_scalar_hex = sys.argv[1]
    c_scalar_hex = sys.argv[2]
    
    # Parse hex scalars
    s_scalar = int(s_scalar_hex, 16)
    c_scalar = int(c_scalar_hex, 16)
    
    # Generate hints
    data = generate_dleq_hints(s_scalar, c_scalar)
    
    # Print results
    print_hints(data)
    
    # Optionally save to JSON
    if "--save" in sys.argv:
        import json
        def convert_large_ints(obj):
            if isinstance(obj, dict):
                return {k: convert_large_ints(v) for k, v in obj.items()}
            elif isinstance(obj, (list, tuple)):
                return [convert_large_ints(item) for item in obj]
            elif isinstance(obj, int):
                if obj > 9007199254740992:  # 2^53
                    return str(obj)
                return obj
            return obj
        
        data_safe = convert_large_ints(data)
        with open("dleq_hints.json", "w") as f:
            json.dump(data_safe, f, indent=2)
        print("\n✅ Saved to dleq_hints.json")


if __name__ == "__main__":
    main()

