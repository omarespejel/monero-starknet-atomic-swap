# DLEQ Verification Testing Plan

## Current Status

**What We Have:**
- ✅ DLEQ verification logic in Cairo (using Poseidon)
- ✅ DLEQ proof generation in Rust (using SHA-256)
- ✅ Refactored MSM operations (single-scalar MSMs)
- ⚠️ Hash function mismatch (Rust SHA-256 ≠ Cairo Poseidon)
- ⚠️ Empty MSM hints (works but inefficient)

**What We Need to Test:**
1. Cairo DLEQ verification logic (self-contained test)
2. MSM operations with empty hints (current state)
3. Input validation (on-curve, small-order, scalar range)
4. End-to-end: Rust proof → Cairo verification (after hash alignment)

---

## Testing Strategy

### Phase 1: Self-Contained Cairo Tests (Works Now)

Test the DLEQ verification logic directly in Cairo using known test vectors.

**Approach:** Generate a proof entirely in Cairo, then verify it.

**Test Cases:**
1. ✅ Valid DLEQ proof (should verify)
2. ❌ Invalid challenge (should fail)
3. ❌ Invalid response (should fail)
4. ❌ Invalid point (off-curve, should fail)
5. ❌ Small-order point (should fail)
6. ❌ Zero scalar (should fail)

### Phase 2: Integration Tests (After Hash Alignment)

Test Rust-generated proofs verifying in Cairo.

**Approach:** Generate proof in Rust, convert to Cairo format, verify in Cairo.

**Requirements:**
- Hash function alignment (Poseidon in both)
- Edwards → Weierstrass conversion
- Proper MSM hints generation

---

## Implementation: Phase 1 Tests

### Test 1: Valid DLEQ Proof (Self-Contained)

```cairo
#[test]
fn test_dleq_verification_valid() {
    // Generate test data entirely in Cairo
    // This tests the verification logic without needing Rust
    
    let curve_idx = 4; // Ed25519
    let G = get_G(curve_idx);
    let Y = get_dleq_second_generator(); // 2·G
    
    // Create a test secret scalar t
    let t_scalar = u256 { low: 0x1234567890abcdef, high: 0 };
    let t_scalar = reduce_scalar_ed25519(t_scalar);
    
    // Compute T = t·G and U = t·Y
    let T = msm_g1(array![G].span(), array![t_scalar].span(), curve_idx, empty_hint());
    let U = msm_g1(array![Y].span(), array![t_scalar].span(), curve_idx, empty_hint());
    
    // Create hashlock (8 u32 words)
    let hashlock = array![
        0x12345678_u32, 0x90abcdef_u32, 0x11111111_u32, 0x22222222_u32,
        0x33333333_u32, 0x44444444_u32, 0x55555555_u32, 0x66666666_u32
    ].span();
    
    // Generate nonce k (deterministic)
    let k = generate_test_nonce(t_scalar, hashlock);
    
    // Compute commitments R1 = k·G, R2 = k·Y
    let R1 = msm_g1(array![G].span(), array![k].span(), curve_idx, empty_hint());
    let R2 = msm_g1(array![Y].span(), array![k].span(), curve_idx, empty_hint());
    
    // Compute challenge c = H(tag, G, Y, T, U, R1, R2, hashlock)
    let c = compute_dleq_challenge(G, Y, T, U, R1, R2, hashlock);
    
    // Compute response s = k + c·t mod n
    let c_t = (c * t_scalar) % ED25519_ORDER;
    let s = (k + c_t) % ED25519_ORDER;
    
    // Convert to felt252 for verification
    let c_felt: felt252 = c.low.try_into().unwrap();
    let s_felt: felt252 = s.low.try_into().unwrap();
    
    // Verify the proof (should succeed)
    // Note: We need to make _verify_dleq_proof accessible for testing
    // Or test via constructor deployment
}
```

### Test 2: Invalid Challenge

```cairo
#[test]
#[should_panic(expected: ('DLEQ: challenge mismatch',))]
fn test_dleq_invalid_challenge() {
    // Same setup as test 1, but tamper with challenge
    let c_felt: felt252 = (c + 1).try_into().unwrap(); // Wrong challenge
    // Deploy contract - should fail in constructor
}
```

### Test 3: Invalid Point (Off-Curve)

```cairo
#[test]
#[should_panic(expected: ('DLEQ: point not on curve',))]
fn test_dleq_off_curve_point() {
    // Create invalid point (not on curve)
    let invalid_T = G1Point {
        x: u384 { limb0: 0xdeadbeef, limb1: 0, limb2: 0, limb3: 0 },
        y: u384 { limb0: 0xbadcafe, limb1: 0, limb2: 0, limb3: 0 }
    };
    // Deploy with invalid point - should fail validation
}
```

---

## Quick Test: Deploy Contract with DLEQ

The simplest way to test right now is to deploy a contract with DLEQ data and see if it succeeds.

**Steps:**
1. Generate test data (secret, adaptor point, DLEQ proof)
2. Convert to Cairo format (Weierstrass coordinates, u384 limbs)
3. Deploy contract - constructor will verify DLEQ
4. If deployment succeeds → DLEQ verification passed ✅
5. If deployment fails → DLEQ verification failed ❌

---

## Test Script: Generate Test Vectors

Create a Python script to generate test vectors that work with Cairo's Poseidon:

```python
# tools/generate_dleq_test_vectors.py
"""
Generate DLEQ test vectors compatible with Cairo's Poseidon hashing.

This generates proofs using the same hash function (Poseidon) that Cairo uses,
ensuring proofs verify correctly.
"""

def generate_cairo_compatible_dleq_proof(secret_scalar, hashlock_u32_words):
    """
    Generate DLEQ proof using Poseidon (matching Cairo).
    
    Returns:
        - T: adaptor point (t·G) in Weierstrass u384 limbs
        - U: second point (t·Y) in Weierstrass u384 limbs  
        - c: challenge (felt252)
        - s: response (felt252)
    """
    # 1. Convert Edwards to Weierstrass
    # 2. Use Poseidon for challenge (matching Cairo)
    # 3. Return in Cairo format
    pass
```

---

## Running Tests

### Cairo Tests

```bash
cd cairo
snforge test test_dleq_verification
```

### Rust Tests

```bash
cd rust
cargo test dleq
```

### Integration Test (After Hash Alignment)

```bash
# Generate proof in Rust
cd rust
cargo run --bin generate_dleq_proof -- --secret <hex> --output proof.json

# Verify in Cairo test
cd cairo
snforge test test_dleq_rust_proof --proof-file ../proof.json
```

---

## Current Limitations

**What Won't Work Yet:**
- ❌ Rust proof → Cairo verification (hash mismatch)
- ❌ End-to-end integration tests

**What Will Work:**
- ✅ Cairo self-contained tests (generate & verify in Cairo)
- ✅ Unit tests for individual functions
- ✅ Validation tests (off-curve, small-order, etc.)

---

## Next Steps

1. **Immediate:** Create self-contained Cairo test for DLEQ verification
2. **Short-term:** Generate test vectors using Poseidon (Python script)
3. **Medium-term:** Align hash functions (Rust → Poseidon)
4. **Long-term:** Full integration tests (Rust → Cairo)

---

## Test Coverage Goals

- [ ] Valid DLEQ proof verification
- [ ] Invalid challenge rejection
- [ ] Invalid response rejection
- [ ] Off-curve point rejection
- [ ] Small-order point rejection
- [ ] Zero scalar rejection
- [ ] MSM operations with empty hints
- [ ] End-to-end Rust → Cairo (after hash alignment)

