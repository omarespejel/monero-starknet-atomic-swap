#!/usr/bin/env python3
"""Generate raw AtomicLock constructor calldata.

The output is suitable for starkli/sncast-style deploy commands. It includes explicit
Span lengths and serializes the DLEQ proof as `(felt252, u256)`.
"""

from __future__ import annotations

import argparse
import json
import os
import time
from pathlib import Path

MASK_128 = (1 << 128) - 1


def normalize_hex(value: int | str) -> str:
    if isinstance(value, int):
        return f"0x{value:x}"
    value = value.strip()
    if value.startswith("0x"):
        return f"0x{int(value, 16):x}"
    return f"0x{int(value):x}"


def le_hex_to_int(value: str) -> int:
    return int.from_bytes(bytes.fromhex(value.removeprefix("0x")), "little")


def le_hex_to_u256(value: str) -> list[str]:
    n = le_hex_to_int(value)
    return [normalize_hex(n & MASK_128), normalize_hex(n >> 128)]


def int_to_u256(value: int) -> list[str]:
    return [normalize_hex(value & MASK_128), normalize_hex(value >> 128)]


def u256_parts(value: dict[str, str]) -> list[str]:
    return [normalize_hex(value["low"]), normalize_hex(value["high"])]


def hashlock_words(value: str) -> list[str]:
    clean = value.removeprefix("0x")
    if len(clean) != 64:
        raise ValueError("hashlock must be 32 bytes")
    return [f"0x{clean[i:i + 8]}" for i in range(0, 64, 8)]


def hint_from_cairo_array(value: str) -> list[str]:
    import re

    felts = re.findall(r"0x[0-9a-fA-F]+", value)
    if len(felts) != 10:
        raise ValueError(f"expected 10 hint felts, got {len(felts)}")
    return [normalize_hex(felt) for felt in felts]


def push_span(calldata: list[str], values: list[str]) -> None:
    calldata.append(normalize_hex(len(values)))
    calldata.extend(normalize_hex(value) for value in values)


def build_calldata(repo: Path, lock_until: int, depositor: str, token: str, amount: int) -> list[str]:
    vectors = json.loads((repo / "rust" / "test_vectors.json").read_text())
    generated = json.loads((repo / "cairo" / "generated_dleq_vectors.json").read_text())
    hints = json.loads((repo / "cairo" / "test_hints.json").read_text())
    adaptor_hint = json.loads((repo / "cairo" / "adaptor_point_hint.json").read_text())

    calldata: list[str] = []
    push_span(calldata, hashlock_words(vectors["hashlock"]))
    calldata.append(normalize_hex(lock_until))
    calldata.append(normalize_hex(depositor))
    calldata.append(normalize_hex(token))
    calldata.extend(int_to_u256(amount))

    calldata.extend(le_hex_to_u256(vectors["adaptor_point_compressed"]))
    calldata.extend(u256_parts(generated["sqrt_hints"]["adaptor_point_sqrt_hint"]))
    calldata.extend(le_hex_to_u256(vectors["second_point_compressed"]))
    calldata.extend(u256_parts(generated["sqrt_hints"]["second_point_sqrt_hint"]))

    calldata.append(normalize_hex(generated["challenge"]))
    calldata.extend(u256_parts(generated["response"]))

    push_span(calldata, hint_from_cairo_array(adaptor_hint["cairo_format"]))
    push_span(calldata, hint_from_cairo_array(hints["cairo_hints"]["s_hint_for_g"]))
    push_span(calldata, hint_from_cairo_array(hints["cairo_hints"]["s_hint_for_y"]))
    push_span(calldata, hint_from_cairo_array(hints["cairo_hints"]["c_neg_hint_for_t"]))
    push_span(calldata, hint_from_cairo_array(hints["cairo_hints"]["c_neg_hint_for_u"]))

    calldata.extend(le_hex_to_u256(vectors["r1_compressed"]))
    calldata.extend(u256_parts(generated["sqrt_hints"]["r1_sqrt_hint"]))
    calldata.extend(le_hex_to_u256(vectors["r2_compressed"]))
    calldata.extend(u256_parts(generated["sqrt_hints"]["r2_sqrt_hint"]))
    return calldata


def main() -> None:
    repo = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument("--lock-until", type=int, default=int(time.time()) + 4 * 60 * 60)
    parser.add_argument(
        "--depositor",
        default=os.getenv("ATOMIC_SWAP_DEPOSITOR", os.getenv("STARKNET_ACCOUNT_ADDRESS", "0x0")),
    )
    parser.add_argument("--token", default=os.getenv("ATOMIC_SWAP_TOKEN_ADDRESS", "0x0"))
    parser.add_argument("--amount", default=os.getenv("ATOMIC_SWAP_AMOUNT", "0"))
    parser.add_argument("--network", default=os.getenv("STARKNET_NETWORK", "sepolia"))
    parser.add_argument("--allow-zero-lock", action="store_true", default=os.getenv("ATOMIC_SWAP_ALLOW_ZERO_LOCK") == "1")
    args = parser.parse_args()

    token = normalize_hex(args.token)
    depositor = normalize_hex(args.depositor)
    amount = int(args.amount, 0) if isinstance(args.amount, str) and args.amount.startswith("0x") else int(args.amount)
    if not args.allow_zero_lock and (token == "0x0" or amount == 0):
        raise SystemExit(
            "Set --token and --amount, or pass --allow-zero-lock for a zero-value test deployment."
        )
    if amount != 0 and depositor == "0x0":
        raise SystemExit("Set --depositor or ATOMIC_SWAP_DEPOSITOR/STARKNET_ACCOUNT_ADDRESS for non-zero token locks.")

    calldata = build_calldata(repo, args.lock_until, depositor, token, amount)
    print(" ".join(calldata))

    out = repo / "deployments" / args.network / "latest_calldata.txt"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(" ".join(calldata) + "\n")


if __name__ == "__main__":
    main()
