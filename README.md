# XMR ↔️ Starknet Atomic Lock PoC

This repo demonstrates a cross-chain hashlock primitive:

- `rust/`: Generates a Monero-compatible scalar and its SHA-256 digest, formatted for Cairo.
- `cairo/`: Starknet contract `AtomicLock` that stores the target hash and unlocks when given the correct secret, plus tests.

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
scarb test   # uses cairo-test plugin; see notes below
```

- Constructor expects 8×u32 hash words, a timelock (`lock_until`), token address, and amount (amount/token can be zero to skip transfers).
- `verify_and_unlock` hashes the provided `ByteArray`, compares words, guards against double unlock, emits `Unlocked`, and if amount>0 transfers ERC20 tokens to the caller.
- `refund` lets the depositor reclaim tokens after `lock_until` if still locked.

### Tests

`tests/test_atomic_lock.cairo` shows an end-to-end flow. Replace the placeholders with fresh values from `cargo run -- --format json`.

If `scarb test` warns about `cairo-test` plugin, ensure `[dev-dependencies] cairo_test = "2.14.0"` is present (already added). For `snforge`, use `snfoundry.toml` in `cairo/`.

## Repository layout

```
rust/   # Rust CLI & lib
cairo/  # Starknet contract + tests
```

