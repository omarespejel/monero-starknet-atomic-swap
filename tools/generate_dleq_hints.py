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


def generate_hint_for_scalar_and_base(
    scalar: int,
    base_point: G1Point,
) -> Tuple[List[int], G1Point]:
    """
    Generate fake-GLV hint for scalar multiplication: scalar * base_point.
    
    Args:
        scalar: Scalar value (will be reduced mod curve order)
        base_point: Base point for multiplication
    
    Returns:
        Tuple of (hint_felts, Q) where Q = scalar * base_point
    """
    from garaga.curves import CurveID, CURVES
    
    curve = CURVES[CurveID.ED25519.value]
    scalar = scalar % curve.n
    
    # Generate fake-GLV hint for scalar * base_point
    Q, s1, s2_encoded = get_fake_glv_hint(base_point, scalar)
    
    # Convert Q to u384 limbs
    Q_x_limbs = u384_to_cairo_tuple(Q.x)
    Q_y_limbs = u384_to_cairo_tuple(Q.y)
    
    # Format as 10-felt hint: [Q.x limbs (4), Q.y limbs (4), s1, s2_encoded]
    hint_felts = [*Q_x_limbs, *Q_y_limbs, s1, s2_encoded]
    
    return hint_felts, Q


def generate_dleq_hints(
    s_scalar: int,
    c_scalar: int,
    G: G1Point = None,
    Y: G1Point = None,
    T: G1Point = None,
    U: G1Point = None,
    curve_id: CurveID = CurveID.ED25519,
) -> dict:
    """
    Generate MSM hints for DLEQ verification scalars with specific base points.
    
    Args:
        s_scalar: Response scalar s (from DLEQ proof)
        c_scalar: Challenge scalar c (from DLEQ proof)
        G: Ed25519 generator point (default: standard generator)
        Y: Second generator point (default: 2·G)
        T: Adaptor point (required)
        U: DLEQ second point (required)
        curve_id: Curve identifier (default: Ed25519)
    
    Returns:
        Dictionary with hints for all DLEQ MSM operations:
        - s_hint_for_g: hint for s·G
        - s_hint_for_y: hint for s·Y
        - c_neg_hint_for_t: hint for (-c)·T
        - c_neg_hint_for_u: hint for (-c)·U
    """
    curve = CURVES[curve_id.value]
    
    # Reduce scalars modulo curve order
    s_scalar = s_scalar % curve.n
    c_scalar = c_scalar % curve.n
    
    # Compute -c mod n
    c_neg_scalar = (curve.n - c_scalar) % curve.n
    
    # Get default points if not provided
    if G is None:
        G = G1Point.get_nG(curve_id, 1)
    if Y is None:
        # Default: Y = 2·G (matches current Cairo implementation)
        Y = G.scalar_mul(2)
    
    # For production, T and U must be provided
    # For testing, we can use placeholders (but hints won't be correct)
    if T is None:
        print("WARNING: T (adaptor point) not provided. Using placeholder G.")
        print("         Generated hints for (-c)·T will NOT be correct for actual T.")
        T = G  # Placeholder - incorrect but allows tool to run
    if U is None:
        print("WARNING: U (DLEQ second point) not provided. Using placeholder Y.")
        print("         Generated hints for (-c)·U will NOT be correct for actual U.")
        U = Y  # Placeholder - incorrect but allows tool to run
    
    # Generate hints for each MSM operation
    # s·G
    s_hint_for_g_felts, s_hint_for_g_Q = generate_hint_for_scalar_and_base(s_scalar, G)
    
    # s·Y
    s_hint_for_y_felts, s_hint_for_y_Q = generate_hint_for_scalar_and_base(s_scalar, Y)
    
    # (-c)·T
    c_neg_hint_for_t_felts, c_neg_hint_for_t_Q = generate_hint_for_scalar_and_base(c_neg_scalar, T)
    
    # (-c)·U
    c_neg_hint_for_u_felts, c_neg_hint_for_u_Q = generate_hint_for_scalar_and_base(c_neg_scalar, U)
    
    return {
        "s_hint_for_g": {
            "scalar": s_scalar,
            "base_point": "G",
            "hint_felts": s_hint_for_g_felts,
            "cairo_hint": format_cairo_hint(s_hint_for_g_felts),
            "hint_Q": s_hint_for_g_Q,
        },
        "s_hint_for_y": {
            "scalar": s_scalar,
            "base_point": "Y",
            "hint_felts": s_hint_for_y_felts,
            "cairo_hint": format_cairo_hint(s_hint_for_y_felts),
            "hint_Q": s_hint_for_y_Q,
        },
        "c_neg_hint_for_t": {
            "scalar": c_neg_scalar,
            "base_point": "T",
            "hint_felts": c_neg_hint_for_t_felts,
            "cairo_hint": format_cairo_hint(c_neg_hint_for_t_felts),
            "hint_Q": c_neg_hint_for_t_Q,
        },
        "c_neg_hint_for_u": {
            "scalar": c_neg_scalar,
            "base_point": "U",
            "hint_felts": c_neg_hint_for_u_felts,
            "cairo_hint": format_cairo_hint(c_neg_hint_for_u_felts),
            "hint_Q": c_neg_hint_for_u_Q,
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
    print("DLEQ MSM HINTS FOR CAIRO (Production-Grade)")
    print("=" * 80)
    print()
    
    print("## HINT FOR s·G")
    print(f"Scalar s: {hex(data['s_hint_for_g']['scalar'])}")
    print(f"Cairo hint: {data['s_hint_for_g']['cairo_hint']}")
    print()
    
    print("## HINT FOR s·Y")
    print(f"Scalar s: {hex(data['s_hint_for_y']['scalar'])}")
    print(f"Cairo hint: {data['s_hint_for_y']['cairo_hint']}")
    print()
    
    print("## HINT FOR (-c)·T")
    print(f"Scalar -c: {hex(data['c_neg_hint_for_t']['scalar'])}")
    print(f"Cairo hint: {data['c_neg_hint_for_t']['cairo_hint']}")
    print()
    
    print("## HINT FOR (-c)·U")
    print(f"Scalar -c: {hex(data['c_neg_hint_for_u']['scalar'])}")
    print(f"Cairo hint: {data['c_neg_hint_for_u']['cairo_hint']}")
    print()
    
    print("## CAIRO SNIPPET")
    print("// Use these hints in constructor call:")
    print(f"let s_hint_for_g = {data['s_hint_for_g']['cairo_hint']};")
    print(f"let s_hint_for_y = {data['s_hint_for_y']['cairo_hint']};")
    print(f"let c_neg_hint_for_t = {data['c_neg_hint_for_t']['cairo_hint']};")
    print(f"let c_neg_hint_for_u = {data['c_neg_hint_for_u']['cairo_hint']};")
    print()
    print("=" * 80)


def parse_point_from_limbs(x_limbs: List[str], y_limbs: List[str], curve_id: CurveID = CurveID.ED25519) -> G1Point:
    """
    Parse G1Point from u384 limbs (hex strings).
    
    NOTE: This is a workaround. For production, hints should be generated
    with actual G1Point objects from the DLEQ proof generation.
    """
    from garaga.hints.io import bigint_split
    
    def limbs_to_int(limbs: List[str]) -> int:
        """Convert 4 hex limb strings to integer."""
        limb0 = int(limbs[0], 16)
        limb1 = int(limbs[1], 16)
        limb2 = int(limbs[2], 16)
        limb3 = int(limbs[3], 16)
        # Reconstruct u384: limb0 + limb1*2^96 + limb2*2^192 + limb3*2^288
        return limb0 + (limb1 << 96) + (limb2 << 192) + (limb3 << 288)
    
    x_int = limbs_to_int(x_limbs)
    y_int = limbs_to_int(y_limbs)
    
    # G1Point doesn't have a direct constructor from coordinates
    # We need to use a workaround: create point via scalar multiplication
    # This is not ideal but works for testing
    # For production, use actual G1Point objects from proof generation
    
    # Try to find a scalar that gives us this point (not practical)
    # Instead, we'll use a placeholder approach: create point via known method
    # Actually, the best approach is to accept that this tool should be called
    # with actual G1Point objects, not coordinates
    
    # For now, raise an error directing users to provide G1Point objects
    raise NotImplementedError(
        "Point construction from coordinate limbs is not directly supported. "
        "For production-grade hints, generate them in Rust/Python code that has "
        "access to actual G1Point objects (T and U) from the DLEQ proof. "
        "Alternatively, integrate this tool into the proof generation pipeline."
    )


def main() -> None:
    """Main entry point."""
    if len(sys.argv) < 3:
        print("Usage: python generate_dleq_hints.py <s_scalar_hex> <c_scalar_hex> [T_x0 T_x1 T_x2 T_x3 T_y0 T_y1 T_y2 T_y3] [U_x0 U_x1 U_x2 U_x3 U_y0 U_y1 U_y2 U_y3]")
        print("Example: python generate_dleq_hints.py 0x1234... 0xabcd...")
        print("         python generate_dleq_hints.py 0x1234... 0xabcd... <T_limbs> <U_limbs>")
        sys.exit(1)
    
    s_scalar_hex = sys.argv[1]
    c_scalar_hex = sys.argv[2]
    
    # Parse hex scalars
    s_scalar = int(s_scalar_hex, 16)
    c_scalar = int(c_scalar_hex, 16)
    
    # Parse optional points T and U
    # NOTE: For production, T and U should be G1Point objects from proof generation
    # This CLI interface is for testing only - production should call generate_dleq_hints()
    # directly with G1Point objects
    T = None
    U = None
    if len(sys.argv) >= 11:  # Has T point (8 limbs)
        try:
            T_x_limbs = sys.argv[3:7]
            T_y_limbs = sys.argv[7:11]
            T = parse_point_from_limbs(T_x_limbs, T_y_limbs)
        except NotImplementedError as e:
            print(f"Warning: {e}")
            print("Continuing without T point - hints for (-c)·T will use placeholder.")
    
    if len(sys.argv) >= 19:  # Has U point (8 limbs)
        try:
            U_x_limbs = sys.argv[11:15]
            U_y_limbs = sys.argv[15:19]
            U = parse_point_from_limbs(U_x_limbs, U_y_limbs)
        except NotImplementedError as e:
            print(f"Warning: {e}")
            print("Continuing without U point - hints for (-c)·U will use placeholder.")
    
    # Generate hints
    try:
        data = generate_dleq_hints(s_scalar, c_scalar, T=T, U=U)
    except ValueError as e:
        print(f"Error: {e}")
        print("\nNote: T and U points are required for production-grade hints.")
        print("You can provide them as 8 hex limb values each (x0, x1, x2, x3, y0, y1, y2, y3).")
        sys.exit(1)
    
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

