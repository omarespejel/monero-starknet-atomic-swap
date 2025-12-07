# CLSAG Test Suite - Layered Testing Strategy

## Overview

This test suite follows a **layered testing approach** recommended by auditors to catch issues early before full integration testing. Tests are organized by level of abstraction, allowing incremental debugging.

## Test Structure

### 1. Unit Tests (`clsag_unit_tests.rs`)

**Purpose**: Test each CLSAG component in isolation

**Coverage**:
- Hash-to-point (Hp) function: Determinism, different inputs, key image computation
- Standard CLSAG: Sign/verify, wrong message rejection, ring sizes
- Adaptor CLSAG: Adaptor point correctness, finalization, extraction, wrong scalar rejection

**Run**: `cargo test --test clsag_unit_tests`

**Status**: 8/11 passing - catching bugs in standard CLSAG verification and adaptor finalization

### 2. DLEQ-CLSAG Integration (`clsag_dleq_integration.rs`)

**Purpose**: Verify the critical bridge between Monero (CLSAG) and Starknet (DLEQ)

**Coverage**:
- Same adaptor scalar used for both protocols (CRITICAL)
- Adaptor point consistency between DLEQ and CLSAG
- Hashlock computation and serialization
- Scalar consistency across multiple runs

**Run**: `cargo test --test clsag_dleq_integration`

**Status**: 2/3 passing - finalization issue affects integration test

### 3. End-to-End Atomic Swap (`atomic_swap_e2e.rs`)

**Purpose**: Full protocol simulation without blockchain interaction

**Coverage**:
- Complete atomic swap flow: Alice creates adaptor sig → Bob unlocks → Alice finalizes
- Wrong secret rejection
- Hashlock verification
- Scalar extraction

**Run**: `cargo test --test atomic_swap_e2e`

**Status**: 1/2 passing - full flow blocked by finalization bug

## Test Execution Order

Run tests in this order to catch issues incrementally:

```bash
# 1. Unit tests first (fast, isolated)
cargo test --test clsag_unit_tests

# 2. DLEQ-CLSAG bridge (critical integration point)
cargo test --test clsag_dleq_integration

# 3. Full flow (catches protocol-level bugs)
cargo test --test atomic_swap_e2e

# 4. Run all together
cargo test
```

## What Each Layer Catches

| Test Layer | Catches Early |
|------------|---------------|
| **Hash-to-point unit** | Wrong Hp() implementation, non-determinism |
| **Standard CLSAG unit** | Ring signature bugs, challenge computation errors |
| **Adaptor CLSAG unit** | Finalization math errors, wrong adjustment formula |
| **DLEQ-CLSAG integration** | Scalar mismatch between protocols, adaptor point inconsistency |
| **E2E flow** | Protocol-level bugs, wrong secret extraction |

## Current Issues Found

### Issue 1: Standard CLSAG Verification Failing
- **Location**: `clsag_unit_tests.rs::test_standard_clsag_sign_verify`
- **Symptom**: Valid signatures don't verify
- **Likely Cause**: Ring closure computation bug in `compute_c1()` or challenge computation

### Issue 2: Adaptor Finalization Producing Invalid Signatures
- **Location**: Multiple tests in `clsag_unit_tests.rs` and integration tests
- **Symptom**: Finalized adaptor signatures don't verify as standard CLSAG
- **Likely Cause**: Wrong adjustment formula in `finalize()` method

## Benefits of Layered Testing

1. **Early Detection**: Bugs caught at unit test level before integration
2. **Focused Debugging**: Know exactly which component has the issue
3. **Incremental Development**: Can fix unit tests before moving to integration
4. **Regression Prevention**: Comprehensive coverage prevents future bugs

## Next Steps

1. Fix standard CLSAG verification (ring closure issue)
2. Fix adaptor finalization formula
3. Re-run unit tests until all pass
4. Then proceed to integration and E2E tests

This approach ensures we don't repeat the DLEQ debugging cycle - issues are caught and fixed at the lowest level first.

