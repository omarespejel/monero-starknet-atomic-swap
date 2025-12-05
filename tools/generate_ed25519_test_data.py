#!/usr/bin/env python3
"""
Generate Ed25519 test data for Cairo MSM verification (AtomicLock).

Outputs:
- Secret scalar t (hex and Cairo u256 literal)
- Adaptor point T = t·G in Weierstrass coordinates (u384 limbs, 4 × 96-bit)
- Fake-GLV hint for MSM (as Cairo array of felts)
"""
import sys
import hashlib
from typing import Tuple, List

from garaga.curves import CurveID, CURVES
from garaga.points import G1Point
from garaga.hints.fake_glv import get_fake_glv_hint
from garaga.hints.io import bigint_split


def scalar_to_hex(scalar: int) -> str:
    return hex(scalar)[2:].zfill(64)


def sha256_words(secret: bytes) -> List[int]:
    digest = hashlib.sha256(secret).digest()
    # Interpret as 8 big-endian u32 words
    return [int.from_bytes(digest[i : i + 4], "big") for i in range(0, 32, 4)]


def u384_to_cairo_tuple(value: int) -> Tuple[int, int, int, int]:
    # Split into 4 limbs base 2^96 (matches Garaga u384 layout)
    return tuple(bigint_split(value, 4, 2**96))


def format_cairo_u384(limbs: Tuple[int, int, int, int]) -> str:
    return f"({', '.join(f'0x{limb:x}' for limb in limbs)})"


def format_cairo_hint(hint_felts: List[int]) -> str:
    return f"array![{', '.join(f'0x{felt:x}' for felt in hint_felts)}].span()"


def generate_ed25519_test_data(secret_hex: str | None = None) -> dict:
    # Use provided 32-byte secret or an example default
    if secret_hex is None:
        secret_hex = "99dd9b73e2e84db472b342dc3ab0520f654fd8a81d644180477730a90af8900"
    secret_hex = secret_hex.strip().lower()
    if secret_hex.startswith("0x"):
        secret_hex = secret_hex[2:]
    secret_hex = secret_hex.zfill(64)
    if len(secret_hex) != 64:
        raise ValueError(f"secret_hex must be 64 hex chars (32 bytes); got len={len(secret_hex)}")
    # Validate hex characters
    int(secret_hex, 16)
    secret_bytes = bytes.fromhex(secret_hex)

    # Hash -> words -> scalar (little-endian u32 limbs) to mirror hash_to_scalar_u256; reduce mod order
    hash_words = sha256_words(secret_bytes)
    scalar_raw = 0
    for i, w in enumerate(hash_words):
        scalar_raw += w << (32 * i)

    curve_id = CurveID.ED25519
    curve = CURVES[curve_id.value]
    scalar_int = scalar_raw % curve.n
    generator = G1Point.get_nG(curve_id, 1)

    adaptor_point = generator.scalar_mul(scalar_int)

    x_limbs = u384_to_cairo_tuple(adaptor_point.x)
    y_limbs = u384_to_cairo_tuple(adaptor_point.y)

    # Fake-GLV hint (returns (Q, s1, s2_encoded)); Q should equal adaptor_point
    Q, s1, s2_encoded = get_fake_glv_hint(generator, scalar_int)
    assert Q == adaptor_point, "MSM hint point mismatch"

    Q_x_limbs = u384_to_cairo_tuple(Q.x)
    Q_y_limbs = u384_to_cairo_tuple(Q.y)

    # 10 felts: Q.x limbs (4) + Q.y limbs (4) + s1 + s2_encoded
    hint_felts = [*Q_x_limbs, *Q_y_limbs, s1, s2_encoded]

    return {
        "secret": {
            "hex": secret_hex,
            "bytes_len": len(secret_bytes),
        },
        "hash_words": hash_words,
        "scalar_raw": {
            "source": "sha256(secret)",
            "hex": hex(scalar_raw)[2:].zfill(64),
            "int": scalar_raw,
            "cairo_u256": f"u256 {{ low: 0x{scalar_raw & ((1 << 128) - 1):032x}, high: 0x{scalar_raw >> 128:032x} }}",
        },
        "scalar": {
            "source": "sha256(secret) mod n",
            "hex": hex(scalar_int)[2:].zfill(64),
            "int": scalar_int,
            "cairo_u256": f"u256 {{ low: 0x{scalar_int & ((1 << 128) - 1):032x}, high: 0x{scalar_int >> 128:032x} }}",
        },
        "adaptor_point": {
            "x": adaptor_point.x,
            "y": adaptor_point.y,
            "x_limbs": x_limbs,
            "y_limbs": y_limbs,
            "cairo_x": format_cairo_u384(x_limbs),
            "cairo_y": format_cairo_u384(y_limbs),
        },
        "fake_glv_hint": {
            "Q_x_limbs": Q_x_limbs,
            "Q_y_limbs": Q_y_limbs,
            "s1": s1,
            "s2_encoded": s2_encoded,
            "felts": hint_felts,
            "cairo_array": format_cairo_hint(hint_felts),
        },
        "curve_info": {
            "name": "ED25519",
            "curve_id": curve_id.value,
            "order": curve.n,
        },
    }


def print_test_data(data: dict) -> None:
    print("=" * 80)
    print("ED25519 TEST DATA FOR CAIRO")
    print("=" * 80)
    print()
    print("## SCALAR (Secret t)")
    print(f"Hex:     {data['scalar']['hex']}")
    print(f"Int:     {data['scalar']['int']}")
    print(f"Cairo:   {data['scalar']['cairo_u256']}")
    print()
    print("## ADAPTOR POINT T = t·G (Weierstrass coordinates)")
    print(f"X limbs: {data['adaptor_point']['x_limbs']}")
    print(f"Y limbs: {data['adaptor_point']['y_limbs']}")
    print()
    print(f"Cairo X: {data['adaptor_point']['cairo_x']}")
    print(f"Cairo Y: {data['adaptor_point']['cairo_y']}")
    print()
    print("## FAKE-GLV HINT for MSM Verification")
    print(f"s1:          {data['fake_glv_hint']['s1']}")
    print(f"s2_encoded:  {data['fake_glv_hint']['s2_encoded']}")
    print(f"Cairo hint:  {data['fake_glv_hint']['cairo_array']}")
    print()
    print("## CAIRO SNIPPET")
    print(
        f"let x_limbs = {data['adaptor_point']['cairo_x']};\n"
        f"let y_limbs = {data['adaptor_point']['cairo_y']};\n"
        f"let hint = {data['fake_glv_hint']['cairo_array']};"
    )
    print()
    print("=" * 80)


def main() -> None:
    secret_hex = None
    save = False
    for arg in sys.argv[1:]:
        if arg == "--save":
            save = True
        else:
            secret_hex = arg
    data = generate_ed25519_test_data(secret_hex)
    print_test_data(data)
    if save:
        import json
        # Convert large integers to strings to preserve precision for Rust/JSON parsers
        def convert_large_ints(obj):
            if isinstance(obj, dict):
                return {k: convert_large_ints(v) for k, v in obj.items()}
            elif isinstance(obj, list):
                return [convert_large_ints(item) for item in obj]
            elif isinstance(obj, int):
                # Convert integers > 2^53 (JavaScript safe integer limit) to strings
                # to avoid JSON parsers converting them to floats
                if obj > 9007199254740992:  # 2^53
                    return str(obj)
                return obj
            return obj
        
        data_safe = convert_large_ints(data)
        with open("ed25519_test_data.json", "w") as f:
            json.dump(data_safe, f, indent=2)
        print("\n✅ Saved to ed25519_test_data.json")


if __name__ == "__main__":
    main()

