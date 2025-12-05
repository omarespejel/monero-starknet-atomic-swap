# XMR ↔️ Starknet Atomic Lock PoC

This repo demonstrates a cross-chain hashlock primitive:

- `rust/`: Generates a Monero-compatible scalar and its SHA-256 digest, formatted for Cairo.
- `cairo/`: Starknet contract `AtomicLock` that stores the target hash and unlocks when given the correct secret, plus tests.
- `tools/`: Python (uv) generator for Ed25519 adaptor points and Garaga FakeGlv hints used in MSM verification.

## Rust (secret generator)

```bash
cd rust
cargo run -- --format human   # pretty output
cargo run -- --format json    # machine-readable (use in CI)
```

The JSON output contains:
- `hash_u32_words`: 8×u32 words (big-endian) for Cairo.
- `cairo_secret_literal`: the byte-string literal to paste into tests.

## Cairo (AtomicLock)

```bash
cd cairo
scarb build
snforge test   # uses snfoundry; cairo-test is not used here
```

- Constructor expects 8×u32 hash words, a timelock (`lock_until`), token address, and amount (amount/token can be zero to skip transfers).
- `verify_and_unlock` hashes the provided `ByteArray`, compares words, guards against double unlock, emits `Unlocked`, and if amount>0 transfers ERC20 tokens to the caller.
- `refund` lets the depositor reclaim tokens after `lock_until` if still locked.

### Tests

`tests/test_atomic_lock.cairo` covers:
- Hashlock happy path (`test_msm_check_with_real_data`, `test_rust_generated_secret`, `test_cryptographic_handshake`)
- Negative paths (`test_wrong_secret_fails`, `test_wrong_hint_fails` expects FakeGLV panic, `test_cannot_unlock_twice`, refund)
- Garaga import sanity checks.

MSM uses Garaga’s FakeGlvHint (10 felts: Q.x limbs, Q.y limbs, s1, s2_encoded) on Ed25519 in Weierstrass form. Scalars are derived as SHA-256(secret) (8×u32, little-endian limbs) then reduced mod the Ed25519 order, matching `hash_to_scalar_u256` + `reduce_scalar_ed25519` on-chain.

To regenerate test vectors:
```bash
cd tools
source .venv/bin/activate
uv run python generate_ed25519_test_data.py --save
```
Then update `cairo/tests/test_atomic_lock.cairo` with the new `hash_words`, `x_limbs`, `y_limbs`, and `cairo_array` (FakeGlvHint) from `tools/ed25519_test_data.json`.

## Repository layout

```
rust/   # Rust CLI & lib
cairo/  # Starknet contract + tests
```

