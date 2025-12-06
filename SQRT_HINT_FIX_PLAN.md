# Sqrt Hint Format Fix Plan

## Auditor's Analysis: CONFIRMED ✅

The auditor correctly identified that:

1. **Root Cause**: Rust's `generate_all_sqrt_hints.rs` uses Montgomery form x-coordinates, but Garaga expects **twisted Edwards x-coordinates**.

2. **Evidence**: Garaga's `decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point` verifies:
   ```cairo
   x^2 = (y^2 - 1) / (d*y^2 + 1)  // Twisted Edwards equation
   ```
   This verification happens BEFORE converting to Weierstrass, confirming sqrt_hint must be twisted Edwards x.

3. **Coordinate System Mismatch**: Montgomery and twisted Edwards are birationally equivalent but have different coordinate representations. Using Montgomery x directly fails the verification.

## Current Status

- ✅ Python script (`generate_sqrt_hints.py`) implements RFC 8032 correctly
- ✅ Works for 3/4 points (adaptor_point, second_point, r2)
- ❌ Fails for R1: `x_sq` is not a quadratic residue

## Issue with R1

For R1 compressed point `39d2f431a9321d695bf83d4f9089c209ae1717332442c5d611ef4aa1426292f7`:
- Rust can decompress it successfully (point is valid)
- Python's RFC 8032 recovery fails: `x_sq` is not a quadratic residue
- This suggests either:
  1. R1 was generated incorrectly (not using proper Edwards compression)
  2. Square root algorithm needs fixing for edge cases
  3. Need to regenerate R1 using correct method

## Solution Options

### Option 1: Fix Python Square Root Algorithm (Recommended)
- Investigate why R1's `x_sq` is not a quadratic residue
- Check if R1 was generated using correct Edwards compression
- Fix square root computation for edge cases

### Option 2: Regenerate Test Vectors
- Regenerate all DLEQ proof components using Python's RFC 8032 method
- Ensure all compressed points have valid twisted Edwards x-coordinates
- Update test vectors with correct sqrt hints

### Option 3: Extract Edwards x from Rust (Complex)
- Decompress point in Rust (works)
- Extract twisted Edwards x-coordinate directly (requires internal API access)
- More complex but guarantees correctness

## Recommended Action

1. **Immediate**: Regenerate test vectors using Python script for points that work
2. **Investigate**: Why R1's `x_sq` is not a quadratic residue
3. **Fix**: Either fix square root algorithm or regenerate R1 correctly
4. **Verify**: Update Cairo tests with correct twisted Edwards sqrt hints
5. **Test**: Run end-to-end test to confirm decompression works

## Next Steps

- [ ] Fix Python square root algorithm for R1 edge case
- [ ] OR regenerate R1 using correct Edwards compression method
- [ ] Regenerate all sqrt hints using Python script
- [ ] Update Cairo test files with correct hints
- [ ] Verify decompression works for all points
- [ ] Run end-to-end test

