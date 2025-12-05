# How to Generate Real MSM Hints for Production

## Overview

The DLEQ verification requires 4 MSM hints:
1. `s_hint_for_g` - Fake-GLV hint for `s·G`
2. `s_hint_for_y` - Fake-GLV hint for `s·Y`
3. `c_neg_hint_for_t` - Fake-GLV hint for `(-c)·T`
4. `c_neg_hint_for_u` - Fake-GLV hint for `(-c)·U`

**Current Status**: Tests use placeholder empty hints. **Production requires real hints.**

## Prerequisites

1. **Install Garaga Python library**:
   ```bash
   # Install garaga Python package (if available)
   # Or use the Cairo library directly
   ```

2. **Have your DLEQ proof values**:
   - `s` (response scalar)
   - `c` (challenge scalar)
   - `T` (adaptor point)
   - `U` (DLEQ second point)

## Method 1: Using the Python Tool (Recommended)

### Step 1: Install Dependencies

```bash
cd tools
# Install garaga Python library if available
# Or ensure Python can import garaga
```

### Step 2: Generate Hints

```python
from generate_dleq_hints import generate_dleq_hints
from garaga.points import G1Point

# Your DLEQ proof values (from Rust)
s_scalar = 0x...  # Your response scalar
c_scalar = 0x...  # Your challenge scalar
T = G1Point(...)  # Your adaptor point
U = G1Point(...)  # Your DLEQ second point

# Generate hints
hints = generate_dleq_hints(
    s_scalar=s_scalar,
    c_scalar=c_scalar,
    T=T,
    U=U,
    curve_id=CurveID.ED25519,
)

# Use the hints
s_hint_for_g = hints["s_hint_for_g"]["cairo_hint"]
s_hint_for_y = hints["s_hint_for_y"]["cairo_hint"]
c_neg_hint_for_t = hints["c_neg_hint_for_t"]["cairo_hint"]
c_neg_hint_for_u = hints["c_neg_hint_for_u"]["cairo_hint"]
```

### Step 3: Update Cairo Contract

Replace the placeholder hints in your contract deployment:

```cairo
// Before (placeholder):
let empty_hint = array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0].span();

// After (real hints):
let s_hint_for_g = array![0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x...].span();
let s_hint_for_y = array![0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x...].span();
let c_neg_hint_for_t = array![0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x...].span();
let c_neg_hint_for_u = array![0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x..., 0x...].span();
```

## Method 2: Integration with Rust Code

### Option A: Generate Hints in Rust

Add hint generation to your Rust DLEQ proof generation:

```rust
// In rust/src/dleq.rs or rust/src/bin/maker.rs

use garaga::hints::fake_glv::get_fake_glv_hint;

pub fn generate_dleq_proof_with_hints(
    secret: &Scalar,
    adaptor_point: &EdwardsPoint,
    hashlock: &[u8; 32],
) -> (DleqProof, DleqHints) {
    // Generate DLEQ proof
    let proof = generate_dleq_proof(secret, adaptor_point, hashlock);
    
    // Generate hints
    let hints = generate_dleq_hints(&proof, adaptor_point);
    
    (proof, hints)
}
```

### Option B: Generate Hints at Deployment Time

Generate hints when deploying the contract:

```rust
// In your deployment script
let proof = generate_dleq_proof(...);
let hints = generate_dleq_hints_for_proof(&proof);
// Pass hints to contract deployment
```

## Method 3: Manual Generation (Advanced)

If you need to generate hints manually:

1. **For each scalar × base point**:
   - Compute `Q = scalar * base_point`
   - Use Garaga's `get_fake_glv_hint(base_point, scalar)` to get hint
   - Format as 10-felt array: `[Q.x limbs (4), Q.y limbs (4), s1, s2_encoded]`

2. **Example for `s·G`**:
   ```python
   Q, s1, s2_encoded = get_fake_glv_hint(G, s_scalar)
   hint = [Q.x.limb0, Q.x.limb1, Q.x.limb2, Q.x.limb3,
           Q.y.limb0, Q.y.limb1, Q.y.limb2, Q.y.limb3,
           s1, s2_encoded]
   ```

## Current Test Status

**Tests currently use placeholder hints** (`array![0, 0, 0...]`). This is intentional:
- ✅ Tests structure validation
- ✅ Tests that contract accepts DLEQ parameters
- ❌ Does NOT test full DLEQ verification (requires real hints)

**For production**: Replace all placeholder hints with real hints generated from your DLEQ proof.

## Verification

After generating hints:

1. **Test locally**:
   ```bash
   cd cairo
   scarb build
   snforge test
   ```

2. **Verify hints are correct**:
   - Hints should be 10 felts each
   - Each hint's Q point should equal `scalar * base_point`
   - Hints should match the scalars and points from your DLEQ proof

## Troubleshooting

### Error: "MSM verification failed"
- **Cause**: Hints don't match the actual scalars/points
- **Solution**: Regenerate hints with correct values

### Error: "Invalid hint length"
- **Cause**: Hint array doesn't have exactly 10 felts
- **Solution**: Ensure hint format is correct (4 x-coord limbs + 4 y-coord limbs + 2 scalars)

### Error: "Hint Q mismatch"
- **Cause**: Hint's Q point doesn't match expected point
- **Solution**: Verify hint generation uses correct base point and scalar

## Next Steps

1. ✅ **Tool exists**: `tools/generate_dleq_hints.py`
2. ⚠️ **Need**: Integration with Rust proof generation
3. ⚠️ **Need**: Update tests to use real hints (or document that tests use placeholders)
4. ⚠️ **Need**: Production deployment script that generates hints

## Related Files

- `tools/generate_dleq_hints.py` - Hint generation tool
- `cairo/src/lib.cairo` - Contract using hints
- `cairo/tests/test_dleq.cairo` - Tests with placeholder hints
- `MSM_HINTS_GUIDE.md` - Detailed MSM hints documentation

