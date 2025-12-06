# Test Strategy for DLEQ Verification

## Problem

The constructor now **always** verifies DLEQ proofs. This means:
- Tests that deploy contracts **must** provide valid DLEQ proofs
- Tests using placeholder DLEQ values will fail deployment
- Tests that don't test DLEQ still need valid DLEQ to deploy

## Test Categories

### 1. Tests That Need Real DLEQ (Unlock/Refund Tests)

These tests need successful deployment to test unlock/refund functionality:
- `test_cryptographic_handshake` - tests unlock
- `test_wrong_secret_fails` - tests unlock with wrong secret  
- `test_cannot_unlock_twice` - tests unlock twice
- `test_refund_after_expiry` - tests refund
- `test_msm_check_with_real_data` - tests unlock
- `test_rust_python_cairo_consistency` - tests unlock
- `test_rust_generated_secret` - tests unlock
- `test_gas_profile_msm_unlock` - tests unlock

**Solution**: These tests should:
1. Use real adaptor points in compressed Edwards format
2. Generate valid DLEQ proofs for those adaptor points
3. Use `deploy_with_dleq` helper or generate DLEQ proofs programmatically

### 2. Constructor Validation Tests (Should Fail)

These tests verify constructor rejects invalid inputs:
- `test_constructor_rejects_zero_point`
- `test_constructor_rejects_wrong_hint_length`
- `test_constructor_rejects_mismatched_hint`
- `test_constructor_rejects_past_lock_time`
- `test_constructor_rejects_mixed_zero_amount_token`
- `test_constructor_rejects_small_order_point`

**Solution**: These tests are **expected to fail** - they test that constructor correctly rejects invalid inputs. The `#[should_panic]` attribute should handle this, but snforge may mark them as failed due to constructor panic handling.

### 3. DLEQ-Specific Tests

These tests specifically test DLEQ verification:
- `test_dleq_contract_deployment_structure` - tests DLEQ structure
- `test_dleq_invalid_proof_rejected` - tests invalid DLEQ rejection
- `test_e2e_dleq_rust_cairo_compatibility` - tests Rust↔Cairo DLEQ compatibility

**Solution**: These already use `deploy_with_dleq` helper with real DLEQ proofs.

## Recommended Approach

### Option 1: Generate Minimal Valid DLEQ Proofs (Recommended)

Create a helper function that generates minimal valid DLEQ proofs for test adaptor points:

```cairo
fn generate_minimal_dleq_proof(
    adaptor_point_compressed: u256,
    adaptor_point_sqrt_hint: u256,
    hashlock: Span<u32>,
) -> (
    u256, // second_point_compressed
    u256, // second_point_sqrt_hint
    felt252, // challenge
    felt252, // response
    Span<felt252>, // s_hint_for_g
    Span<felt252>, // s_hint_for_y
    Span<felt252>, // c_neg_hint_for_t
    Span<felt252>, // c_neg_hint_for_u
    u256, // r1_compressed
    u256, // r1_sqrt_hint
    u256, // r2_compressed
    u256, // r2_sqrt_hint
) {
    // Generate valid DLEQ proof using test vectors or computed values
    // This requires:
    // 1. Computing U = t·Y from adaptor point T = t·G
    // 2. Generating R1, R2 commitment points
    // 3. Computing challenge c = BLAKE2s(G, Y, T, U, R1, R2, hashlock)
    // 4. Computing response s = r + c·t mod q
    // 5. Generating MSM hints
}
```

**Pros**: Tests can use real adaptor points, full DLEQ verification works
**Cons**: Complex to implement, requires DLEQ proof generation logic

### Option 2: Use Test Vectors (Current Approach)

Use the test vectors from `test_e2e_dleq.cairo` for tests that need valid DLEQ:

**Pros**: Simple, uses existing validated test data
**Cons**: Tests can't use their own adaptor points, must use test vector adaptor points

### Option 3: Mark Tests as Expected to Fail (Temporary)

For now, mark tests that need deployment but don't have real DLEQ as `#[ignore]` or document them as "needs DLEQ proof generation":

**Pros**: Quick fix, doesn't break CI
**Cons**: Tests don't run, functionality not verified

## Current Status

- ✅ DLEQ-specific tests use real DLEQ proofs
- ✅ Constructor validation tests are marked with `#[should_panic]`
- ⚠️ Unlock/refund tests use placeholder DLEQ (will fail deployment)
- ⚠️ Need to either:
  1. Generate DLEQ proofs for test adaptor points, OR
  2. Update tests to use test vector adaptor points

## Next Steps

1. **Short-term**: Update unlock/refund tests to use test vector adaptor points and DLEQ proofs
2. **Long-term**: Implement DLEQ proof generation helper for arbitrary adaptor points

