# Security Fix: Single-Party → Two-Party Key Generation

**Date**: December 23, 2025  
**Severity**: CRITICAL  
**Internal ID**: SECURITY-2025-001

## Vulnerability Description

The original implementation used single-party key generation where Alice
generated the full Monero spend key (`full_spend_key = partial_key + adaptor_scalar`).
This allowed Alice to unilaterally spend XMR without Bob's cooperation,
breaking atomic swap atomicity guarantees.

## Attack Scenario

1. Alice generates `SwapKeyPair` (knows full secret)
2. Alice deploys Starknet contract with hashlock
3. Bob sends XMR to shared address
4. Alice spends XMR immediately (she knows full key)
5. Alice never reveals secret on Starknet
6. Bob loses XMR, Alice keeps both XMR and Starknet tokens

## Fix Implementation

Migrated to COMIT-standard two-party key split:

- Alice generates `s_a` (her share only)
- Bob generates `s_b` (his share only)
- Full key `s = s_a + s_b` only constructible after Bob reveals `s_b` on Starknet

## Files Changed

| File | Change |
|------|--------|
| `rust/src/monero/two_party_keys.rs` | NEW: Two-party key generation |
| `rust/src/monero/mod.rs` | Export new module |
| `rust/src/dleq.rs` | Add `generate_dleq_proof_for_bob()` |
| `rust/src/dleq/ed25519_bn254.rs` | NEW: Safe scalar conversion |
| `rust/tests/fixtures/deprecated/` | Moved old vectors |
| `rust/tests/fixtures/protocol/` | NEW: Two-party vectors |

## Test Migration

- **Deprecated**: `tests/fixtures/deprecated/single_party_vectors_UNSAFE.json`
- **New Primary**: `tests/fixtures/protocol/two_party_key_exchange_vectors.json`
- **Regression**: Old tests kept with `#[ignore]` for audit trail

## Verification Commands

```bash
# Run all security tests
cargo test --test scalar_conversion_safety_test
cargo test --test two_party_keys_test
cargo test --test dleq_bob_secret_test

# Verify deprecated tests are ignored
cargo test --test test_deprecated -- --ignored 2>&1 | grep -c "DEPRECATED"
```

## Auditor Sign-off

- [x] First Auditor: Verified implementation matches COMIT pattern
- [x] Second Auditor: Verified Ed25519→BN254 conversion safety
- [ ] External Audit: Pending (recommend before mainnet)

## References

- COMIT Network: https://comit.network/blog/2020/10/06/monero-bitcoin/
- Light Protocol Issue: https://github.com/Lightprotocol/light-protocol/issues/237
- Eth-XMR Atomic Swap Paper: AthanorLabs research
- Cypher Stack Audit: monero-oxide May 2025

