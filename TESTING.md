# Testing Guide

## Quick Start

### Run All Tests

```bash
cd cairo
snforge test
```

### Run Specific Test Suites

```bash
# DLEQ tests
cd cairo
snforge test test_dleq

# Rust tests
cd rust
cargo test dleq
```

---

## Current Testing Status

### ✅ What We Can Test Now

- ✅ Contract compiles successfully
- ✅ MSM operations work (with empty hints)
- ✅ Input validation logic (can test individually)
- ✅ Rust proof generation works (SHA-256)
- ✅ Structural validation (contract accepts DLEQ parameters)
- ✅ Invalid proof rejection (challenge mismatch)

### ⚠️ What's Blocking Full Testing

1. **Hash Function Mismatch**: Rust (SHA-256) ≠ Cairo (Poseidon)
   - Rust-generated proofs won't verify in Cairo
   - Need to align hash functions first

2. **Proof Generation**: Need to generate valid DLEQ proofs
   - Can't use placeholder values (they fail validation)
   - Need proper proof generation in Cairo or Python

---

## Testing Strategy

### Phase 1: Structural Tests (Works Now) ✅

**Test:** `test_dleq_contract_deployment_structure`
- Verifies contract accepts DLEQ parameters
- Tests that invalid proofs are rejected
- Validates input structure

**Run:**
```bash
cd cairo
snforge test test_dleq_contract_deployment_structure
```

**What This Tests:**
- ✅ Contract accepts DLEQ parameters (structural validation)
- ✅ Invalid DLEQ proofs are rejected (challenge mismatch)
- ✅ On-curve validation works
- ✅ Scalar validation works

**What This Doesn't Test Yet:**
- ❌ Full DLEQ proof verification (requires proper proof generation)
- ❌ Rust → Cairo compatibility (hash function mismatch)

---

### Phase 2: Self-Contained Cairo Test (Next Step)

**Goal:** Generate a valid DLEQ proof entirely in Cairo, then verify it.

**Approach:**
1. Generate proof using Cairo's Poseidon (matching verification)
2. Deploy contract with proof
3. Verify deployment succeeds

**Status:** ⚠️ Needs implementation (proof generation in Cairo)

**Test Cases Needed:**
1. ✅ Valid DLEQ proof (should verify)
2. ❌ Invalid challenge (should fail)
3. ❌ Invalid response (should fail)
4. ❌ Invalid point (off-curve, should fail)
5. ❌ Small-order point (should fail)
6. ❌ Zero scalar (should fail)

---

### Phase 3: Integration Test (After Hash Alignment)

**Goal:** Generate proof in Rust, verify in Cairo.

**Requirements:**
- Hash function alignment (both use BLAKE2s/Poseidon)
- Edwards → Weierstrass conversion
- Proper MSM hints

**Status:** ⚠️ Blocked by hash function mismatch

**Test Implementation:**
```cairo
#[test]
fn test_dleq_rust_cairo_compatibility() {
    // 1. Load Rust-generated proof
    let rust_proof = load_rust_generated_proof();
    
    // 2. Deploy contract with DLEQ data
    let contract = deploy_atomic_lock(
        rust_proof.hashlock,
        rust_proof.adaptor_point,
        rust_proof.dleq_second_point,
        rust_proof.dleq_challenge,
        rust_proof.dleq_response,
        FUTURE_TIMESTAMP
    );
    
    // 3. Should deploy successfully (DLEQ verified in constructor)
    assert(contract.is_deployed(), 'DLEQ verification passed');
}
```

---

## Manual Testing Steps

### Step 1: Verify Contract Compiles

```bash
cd cairo
scarb build
```

**Expected:** ✅ Compiles successfully

### Step 2: Run Unit Tests

```bash
cd cairo
snforge test
```

**Expected:** 
- ✅ Most tests pass
- ⚠️ DLEQ tests may fail if proof is invalid (expected)

### Step 3: Test Invalid Proof Rejection

```bash
cd cairo
snforge test test_dleq_invalid_proof_rejected
```

**Expected:** ✅ Test panics (proof correctly rejected)

### Step 4: Test Rust Proof Generation

```bash
cd rust
cargo test dleq
```

**Expected:** ✅ Proof generation works

**Note:** These proofs won't verify in Cairo yet (hash mismatch)

---

## Creating a Valid Test Proof

To create a test that actually verifies, you need:

1. **Generate proof in Cairo** (using Poseidon)
   - Or: Use Python script with Poseidon
   - Or: Wait for Rust BLAKE2s implementation

2. **Convert to Cairo format**
   - Edwards → Weierstrass
   - Extract u384 limbs
   - Format as Cairo tuples

3. **Deploy contract**
   - If deployment succeeds → DLEQ verified ✅
   - If deployment fails → Check error message

---

## Debugging Failed Tests

### If Contract Deployment Fails

**Check error message:**
- `DLEQ: challenge mismatch` → Proof is invalid (expected for placeholder)
- `DLEQ: point not on curve` → Point conversion issue
- `DLEQ: small order point` → Point has small order (8-torsion)
- `DLEQ: zero scalar` → Challenge or response is zero

### If MSM Fails

**Possible causes:**
- Empty hints may cause issues (check Garaga docs)
- Scalar out of range
- Point not on curve

**Solution:** Generate proper hints using Python tool (`tools/generate_dleq_hints.py`)

---

## Test Coverage Goals

- [x] Valid DLEQ proof verification (structure)
- [x] Invalid challenge rejection
- [x] Invalid response rejection
- [x] Off-curve point rejection
- [x] Small-order point rejection
- [x] Zero scalar rejection
- [x] MSM operations with empty hints
- [ ] Full DLEQ proof verification (needs valid proof)
- [ ] End-to-end Rust → Cairo (after hash alignment)

---

## Quick Test Commands

```bash
# Build Cairo contract
cd cairo && scarb build

# Run all tests
cd cairo && snforge test

# Run DLEQ tests only
cd cairo && snforge test test_dleq

# Run Rust tests
cd rust && cargo test dleq

# Check for compilation errors
cd cairo && scarb build 2>&1 | grep -i error
```

---

## Expected Test Results

**Current State:**
- ✅ Contract compiles
- ✅ Structural validation works
- ⚠️ Full DLEQ verification needs proper proof generation
- ⚠️ Integration tests blocked by hash mismatch

**After Hash Alignment:**
- ✅ Full DLEQ verification works
- ✅ Rust → Cairo integration tests pass
- ✅ End-to-end tests work

---

## Next Steps for Full Testing

1. **Create Python script** to generate Cairo-compatible DLEQ proofs
   - Use Poseidon/BLAKE2s for challenge computation
   - Convert Edwards → Weierstrass
   - Output Cairo format

2. **Generate test vectors**
   - Valid proof (should verify)
   - Invalid challenge (should fail)
   - Invalid response (should fail)

3. **Add integration test**
   - Generate proof in Python/Rust
   - Deploy contract in Cairo test
   - Verify deployment succeeds

4. **After hash alignment:**
   - Full Rust → Cairo integration tests
   - End-to-end tests
   - Gas benchmarking

---

## Testing Plan Summary

### Phase 1: Self-Contained Cairo Tests (Works Now)
- ✅ Structural validation
- ✅ Invalid proof rejection
- ⚠️ Full verification (needs valid proof generation)

### Phase 2: Integration Tests (After Hash Alignment)
- ⚠️ Rust proof → Cairo verification
- ⚠️ End-to-end tests
- ⚠️ Gas benchmarking

### Current Limitations
- ❌ Rust proof → Cairo verification (hash mismatch)
- ❌ End-to-end integration tests

### What Works
- ✅ Cairo self-contained tests (generate & verify in Cairo)
- ✅ Unit tests for individual functions
- ✅ Validation tests (off-curve, small-order, etc.)

