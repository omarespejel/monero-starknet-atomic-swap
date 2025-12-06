# Production-Grade MSM Hints for DLEQ Verification

## Overview

This document explains how to generate and use production-grade MSM (Multi-Scalar Multiplication) hints for DLEQ verification in the Cairo contract.

## What Are MSM Hints?

Garaga's `msm_g1` function requires **fake-GLV hints** for efficient scalar multiplication. These hints are 10-felt arrays that contain:
- Q.x limbs (4 felts): The x-coordinate of the result point Q = scalar * base_point
- Q.y limbs (4 felts): The y-coordinate of the result point Q
- s1 (1 felt): Scalar component for GLV decomposition
- s2_encoded (1 felt): Encoded scalar component

**Critical**: The hint Q **must equal** the actual result point (scalar * base_point) for verification to pass.

## DLEQ Verification Requires 4 Hints

The DLEQ verification performs 4 MSM operations, each requiring its own hint:

1. **s·G**: Response scalar `s` multiplied by generator `G`
   - Hint: `s_hint_for_g` (Q = s·G)

2. **s·Y**: Response scalar `s` multiplied by second generator `Y`
   - Hint: `s_hint_for_y` (Q = s·Y)

3. **(-c)·T**: Negated challenge scalar `-c` multiplied by adaptor point `T`
   - Hint: `c_neg_hint_for_t` (Q = (-c)·T)

4. **(-c)·U**: Negated challenge scalar `-c` multiplied by DLEQ second point `U`
   - Hint: `c_neg_hint_for_u` (Q = (-c)·U)

## Generating Hints

### Method 1: Using the Python Tool (Recommended for Testing)

The `tools/generate_dleq_hints.py` tool generates hints for given scalars and base points.

**Prerequisites**:
```bash
cd tools
# Install garaga Python package if available
# Or ensure Python can import garaga
```

**Usage**:
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

**Command Line Usage**:
```bash
cd tools
python generate_dleq_hints.py <s_scalar_hex> <c_scalar_hex>
```

**Example**:
```bash
python generate_dleq_hints.py 0xfedcba0987654321 0x1234567890abcdef
```

**Output**: Cairo-formatted hints for all 4 MSM operations.

**Limitations**:
- Currently requires G1Point objects for T and U (not just coordinates)
- For production, integrate into Rust proof generation pipeline

### Method 2: Generate in Rust (Production)

For production, generate hints **during DLEQ proof creation** in Rust, where you have access to actual `EdwardsPoint` objects that can be converted to `G1Point`.

**Integration Point**: In `rust/src/dleq.rs`, after generating the DLEQ proof:

```rust
use garaga::hints::fake_glv::get_fake_glv_hint;
use garaga::points::G1Point;

// After generating proof with scalars s and c
let proof = generate_dleq_proof(&secret, &adaptor_point, &hashlock);

// Convert Edwards points to Weierstrass (G1Point)
let T_weierstrass = edwards_to_weierstrass(&adaptor_point);
let U_weierstrass = edwards_to_weierstrass(&proof.second_point);
let G_weierstrass = edwards_to_weierstrass(&G);
let Y_weierstrass = edwards_to_weierstrass(&Y);

// Generate hints
let (sG_Q, s1_sG, s2_sG) = get_fake_glv_hint(G_weierstrass, proof.response);
let (sY_Q, s1_sY, s2_sY) = get_fake_glv_hint(Y_weierstrass, proof.response);
let c_neg = (ED25519_ORDER - proof.challenge) % ED25519_ORDER;
let (cT_Q, s1_cT, s2_cT) = get_fake_glv_hint(T_weierstrass, c_neg);
let (cU_Q, s1_cU, s2_cU) = get_fake_glv_hint(U_weierstrass, c_neg);

// Format as 10-felt hints
let s_hint_for_g = format_hint(sG_Q, s1_sG, s2_sG);
let s_hint_for_y = format_hint(sY_Q, s1_sY, s2_sY);
let c_neg_hint_for_t = format_hint(cT_Q, s1_cT, s2_cT);
let c_neg_hint_for_u = format_hint(cU_Q, s1_cU, s2_cU);
```

## Using Hints in Cairo Contract

### Constructor Signature

The constructor now accepts 4 DLEQ hint parameters:

```cairo
fn constructor(
    // ... other parameters ...
    dleq_s_hint_for_g: Span<felt252>,      // Hint for s·G
    dleq_s_hint_for_y: Span<felt252>,      // Hint for s·Y
    dleq_c_neg_hint_for_t: Span<felt252>,  // Hint for (-c)·T
    dleq_c_neg_hint_for_u: Span<felt252>,  // Hint for (-c)·U
)
```

### Validation

Each hint must be exactly 10 felts:
- `assert(dleq_s_hint_for_g.len() == 10, Errors::INVALID_HINT_LENGTH);`
- Similar checks for other hints

### Usage in Verification

Hints are passed to `msm_g1` calls:

```cairo
let sG = msm_g1(
    array![G].span(),
    array![s_scalar].span(),
    curve_idx,
    s_hint_for_g  // ✅ Production-grade hint
);
```

## Testing

### Current Test Status

Tests currently use **empty hints** (`array![0, 0, 0, 0, 0, 0, 0, 0, 0, 0]`) as placeholders. These will cause MSM verification to fail, but allow testing of:
- Constructor parameter validation
- DLEQ proof structure
- Error handling

### Generating Test Hints

To test with real hints:

1. Generate a valid DLEQ proof (requires Rust Poseidon implementation)
2. Extract scalars `s` and `c` from the proof
3. Extract points `T` and `U` from the proof
4. Generate hints using `tools/generate_dleq_hints.py` or Rust integration
5. Update test to use generated hints

## Production Checklist

- [ ] **Rust Integration**: Generate hints during DLEQ proof creation
- [ ] **Point Conversion**: Convert Edwards points to Weierstrass (G1Point) correctly
- [ ] **Hint Validation**: Verify hint Q matches actual result point
- [ ] **Integration Tests**: Test end-to-end with real hints
- [ ] **Gas Optimization**: Measure gas costs with production hints vs empty hints

## Current Status

✅ **Completed**:
- Cairo constructor accepts DLEQ hints as parameters
- `_verify_dleq_proof` uses provided hints instead of empty arrays
- Python tool structure created (needs garaga package for full functionality)
- Test structure updated to pass hints

⚠️ **Remaining**:
- Rust integration for hint generation during proof creation
- Full integration tests with real hints
- Gas benchmarking

## References

- Garaga MSM documentation: [Garaga GitHub](https://github.com/keep-starknet-strange/garaga)
- Fake-GLV hints: See `garaga/hints/fake_glv.py`
- DLEQ proof generation: `rust/src/dleq.rs`

