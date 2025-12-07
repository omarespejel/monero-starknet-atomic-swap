# AI Context: Monero-Starknet Atomic Swap

## Project State (Updated: 2025-12-07)

### Version

0.7.1 - Key Splitting Approach (replaces custom CLSAG)

### What Works ✅

- Key splitting: `SwapKeyPair::generate()`, `::recover()`
- DLEQ proof generation (Rust) and verification (Cairo)
- E2E Rust↔Cairo compatibility test passes
- Security tests: 9/9 passing
- Token tests: 6/6 passing
- Property-based tests: 5/5 passing
- Edge case tests: 4/4 passing
- **Total: 32 tests passing**

### What's Broken ❌

- CI workflows (dependency conflicts) - use `[skip ci]` for now
- CI blocked by `cairo_test v2.8.2` vs `starknet ^2.10.0` conflict

### Recent Decisions

| Decision | Rationale |
|----------|-----------|
| Key splitting over CLSAG adaptor | Serai pattern, audited, simpler |
| BLAKE2s over Poseidon | 8x gas savings |
| curve25519-dalek | Quarkslab audited, constant-time by default |

### Auditor Feedback Summary

1. **P0**: ✅ Add domain separation to nonce generation - DONE
2. **P0**: ✅ Add input validation (zero scalar check) - DONE
3. **P1**: ✅ Add property-based tests - DONE
4. **P1**: ✅ Add edge case tests - DONE
5. **Skip**: Constant-time concern (dalek already handles)

### Key Insight

> "You don't modify CLSAG - you split the key" - Tari RFC-0241

### Files Changed Recently

- `rust/src/monero/key_splitting.rs` - New module
- `rust/src/dleq.rs` - Added input validation, edge case tests
- `rust/tests/dleq_properties.rs` - Property-based tests
- `rust/tests/atomic_swap_e2e.rs` - E2E tests
- `rust/tests/key_splitting_dleq_integration.rs` - Integration tests
- Deleted: `rust/src/clsag/*` (500+ lines of buggy code)

### Test Commands

```bash
cd rust && cargo test                           # 32 tests
cd cairo && scarb test                          # 107 tests  
python tools/verify_full_compatibility.py       # Cross-platform
```

### Don't Touch (Working & Verified)

- `cairo/src/blake2s_challenge.cairo` - RFC 7693 compliant
- ED25519 constants in `cairo/src/lib.cairo` - Verified against RFC 8032
- `rust/src/dleq.rs` (DLEQ generation logic) - All tests passing

### Next Tasks (Priority Order)

1. Fix CI workflows (dependency conflicts)
2. Add Transcript abstraction (P1 - deferred)
3. External security audit preparation

