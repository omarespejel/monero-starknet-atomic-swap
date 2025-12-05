# How to Test DLEQ Verification

## Quick Start: Test What We Have

### 1. Run Existing Tests

```bash
cd cairo
snforge test
```

This runs all tests including the new DLEQ tests.

### 2. Test DLEQ Verification Logic

```bash
cd cairo
snforge test test_dleq
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

### Phase 2: Self-Contained Cairo Test (Next Step)

**Goal:** Generate a valid DLEQ proof entirely in Cairo, then verify it.

**Approach:**
1. Generate proof using Cairo's Poseidon (matching verification)
2. Deploy contract with proof
3. Verify deployment succeeds

**Status:** ⚠️ Needs implementation (proof generation in Cairo)

### Phase 3: Integration Test (After Hash Alignment)

**Goal:** Generate proof in Rust, verify in Cairo.

**Requirements:**
- Hash function alignment (both use Poseidon)
- Edwards → Weierstrass conversion
- Proper MSM hints

**Status:** ⚠️ Blocked by hash function mismatch

---

## Current Test Coverage

### ✅ What Works

1. **Input Validation**
   - On-curve point validation
   - Small-order point rejection
   - Scalar range checks
   - Zero scalar rejection

2. **Structural Tests**
   - Contract accepts DLEQ parameters
   - Invalid proofs cause deployment failure

3. **MSM Operations**
   - Single-scalar MSM works (with empty hints)
   - Point addition works

### ⚠️ What's Limited

1. **Full DLEQ Verification**
   - Can't test end-to-end yet (hash mismatch)
   - Need proper proof generation

2. **MSM Hints**
   - Using empty hints (works but inefficient)
   - Need proper hint generation for production

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
   - Or: Wait for Rust Poseidon implementation

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

**Solution:** Generate proper hints using Python tool

---

## Next Steps for Full Testing

1. **Create Python script** to generate Cairo-compatible DLEQ proofs
   - Use Poseidon for challenge computation
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

