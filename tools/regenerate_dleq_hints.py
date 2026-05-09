#!/usr/bin/env python3
"""
Regenerate Cairo DLEQ vectors and Garaga fake-GLV hints from rust/test_vectors.json.

The production contract verifies the full Poseidon Fiat-Shamir challenge and the full
Ed25519 response scalar. Older scripts intentionally truncated both values to 128 bits;
do not reintroduce that truncation.
"""

import argparse
import json
from pathlib import Path

from garaga.curves import CURVES, CurveID
from garaga.hints.fake_glv import get_fake_glv_hint
from garaga.points import G1Point

ED25519_ORDER = 2**252 + 27742317777372353535851937790883648493
MASK_96 = (1 << 96) - 1
MASK_128 = (1 << 128) - 1


def le_hex_to_int(value: str) -> int:
    return int.from_bytes(bytes.fromhex(value.removeprefix("0x")), "little")


def le_hex_to_u256(value: str) -> tuple[int, int]:
    n = le_hex_to_int(value)
    return n & MASK_128, n >> 128


def int_to_u256(value: int) -> dict[str, str]:
    return {
        "low": f"0x{value & MASK_128:x}",
        "high": f"0x{value >> 128:x}",
    }


def int_to_le_hex32(value: int) -> str:
    return value.to_bytes(32, "little").hex()


def u384_to_limbs(value: int) -> list[int]:
    return [(value >> (96 * i)) & MASK_96 for i in range(4)]


def format_hint(values: list[int]) -> str:
    return "array![" + ", ".join(f"0x{value:x}" for value in values) + "].span()"


def format_u256(low: int, high: int) -> str:
    return f"u256 {{ low: 0x{low:x}, high: 0x{high:x} }}"


def decompress_edwards_point(compressed_hex: str, sqrt_hint_hex: str) -> G1Point:
    curve = CURVES[CurveID.ED25519.value]
    p = curve.p
    d = curve.d_twisted

    compressed_int = le_hex_to_int(compressed_hex)
    sign_bit = (compressed_int >> 255) & 1
    y = compressed_int & ((1 << 255) - 1)
    x = le_hex_to_int(sqrt_hint_hex) % p

    y2 = (y * y) % p
    numerator = (y2 - 1) % p
    denominator = (d * y2 + 1) % p
    expected_x2 = (numerator * pow(denominator, p - 2, p)) % p

    if (x & 1) != sign_bit:
        x = (p - x) % p

    if (x * x) % p != expected_x2:
        other = (p - x) % p
        if (other * other) % p != expected_x2:
            raise ValueError(f"invalid sqrt hint for {compressed_hex}")
        x = other

    wx, wy = curve.to_weierstrass(x, y)
    return G1Point(wx, wy, curve_id=CurveID.ED25519)


def sqrt_hint_from_compressed(compressed_hex: str) -> int:
    curve = CURVES[CurveID.ED25519.value]
    p = curve.p
    d = curve.d_twisted
    sqrt_m1 = pow(2, (p - 1) // 4, p)

    compressed_int = le_hex_to_int(compressed_hex)
    sign_bit = (compressed_int >> 255) & 1
    y = compressed_int & ((1 << 255) - 1)

    y2 = (y * y) % p
    numerator = (y2 - 1) % p
    denominator = (d * y2 + 1) % p
    x2 = (numerator * pow(denominator, p - 2, p)) % p

    x = pow(x2, (p + 3) // 8, p)
    if (x * x) % p != x2:
        x = (x * sqrt_m1) % p
    if (x * x) % p != x2:
        raise ValueError(f"no square root for {compressed_hex}")
    if (x & 1) != sign_bit:
        x = (p - x) % p
    return x


def fake_glv_hint(point: G1Point, scalar: int) -> list[int]:
    q, s1, s2 = get_fake_glv_hint(point, scalar)
    return [*u384_to_limbs(q.x), *u384_to_limbs(q.y), s1, s2]


def main() -> None:
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--vectors-path",
        type=Path,
        default=repo / "rust" / "test_vectors.json",
        help="Input DLEQ vector JSON. Defaults to the checked-in test vector.",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=repo / "cairo",
        help="Directory for generated_dleq_vectors.json, adaptor_point_hint.json, and test_hints.json.",
    )
    args = parser.parse_args()

    vectors_path = args.vectors_path
    with vectors_path.open() as f:
        vectors = json.load(f)

    challenge = le_hex_to_int(vectors["challenge"]) % ED25519_ORDER
    response = le_hex_to_int(vectors["response"]) % ED25519_ORDER
    secret = le_hex_to_int(vectors["secret"]) % ED25519_ORDER
    c_neg = (ED25519_ORDER - challenge) % ED25519_ORDER

    g = G1Point.get_nG(CurveID.ED25519, 1)
    y_sqrt_hint = sqrt_hint_from_compressed(vectors["y_compressed"])
    y = decompress_edwards_point(vectors["y_compressed"], int_to_le_hex32(y_sqrt_hint))
    t = decompress_edwards_point(
        vectors["adaptor_point_compressed"],
        vectors["adaptor_point_sqrt_hint"],
    )
    u = decompress_edwards_point(
        vectors["second_point_compressed"],
        vectors["second_point_sqrt_hint"],
    )

    fake_glv = fake_glv_hint(g, secret)
    msm_hints = {
        "s_hint_for_g": fake_glv_hint(g, response),
        "s_hint_for_y": fake_glv_hint(y, response),
        "c_neg_hint_for_t": fake_glv_hint(t, c_neg),
        "c_neg_hint_for_u": fake_glv_hint(u, c_neg),
    }

    sqrt_hints = {
        "adaptor_point_sqrt_hint": int_to_u256(sqrt_hint_from_compressed(vectors["adaptor_point_compressed"])),
        "second_point_sqrt_hint": int_to_u256(sqrt_hint_from_compressed(vectors["second_point_compressed"])),
        "r1_sqrt_hint": int_to_u256(sqrt_hint_from_compressed(vectors["r1_compressed"])),
        "r2_sqrt_hint": int_to_u256(sqrt_hint_from_compressed(vectors["r2_compressed"])),
    }

    challenge_felt = f"0x{challenge:x}"
    response_u256 = int_to_u256(response)

    generated = {
        "challenge": challenge_felt,
        "response": response_u256,
        "secret_scalar": int_to_u256(secret),
        "c_neg": int_to_u256(c_neg),
        "sqrt_hints": sqrt_hints,
        "second_generator": {
            "compressed": vectors["y_compressed"],
            "compressed_u256": int_to_u256(le_hex_to_int(vectors["y_compressed"])),
            "sqrt_hint": int_to_u256(y_sqrt_hint),
            "weierstrass_x_limbs": [f"0x{value:x}" for value in u384_to_limbs(y.x)],
            "weierstrass_y_limbs": [f"0x{value:x}" for value in u384_to_limbs(y.y)],
        },
        "fake_glv_hint": fake_glv,
        "msm_hints": msm_hints,
        "cairo_hints": {key: format_hint(value) for key, value in msm_hints.items()},
    }

    cairo_dir = args.output_dir
    cairo_dir.mkdir(parents=True, exist_ok=True)
    with (cairo_dir / "generated_dleq_vectors.json").open("w") as f:
        json.dump(generated, f, indent=2)
        f.write("\n")

    with (cairo_dir / "adaptor_point_hint.json").open("w") as f:
        json.dump(
            {
                "adaptor_point_hint": fake_glv,
                "fake_glv_hint": fake_glv,
                "scalar": f"0x{secret:x}",
                "cairo_format": format_hint(fake_glv),
            },
            f,
            indent=2,
        )
        f.write("\n")

    with (cairo_dir / "test_hints.json").open("w") as f:
        json.dump({**msm_hints, "cairo_hints": generated["cairo_hints"]}, f, indent=2)
        f.write("\n")

    print("Regenerated full-scalar DLEQ data")
    print(f"  challenge: {challenge_felt}")
    print(f"  response:  {format_u256(int(response_u256['low'], 16), int(response_u256['high'], 16))}")
    print(f"  c_neg:     {generated['c_neg']}")


if __name__ == "__main__":
    main()
