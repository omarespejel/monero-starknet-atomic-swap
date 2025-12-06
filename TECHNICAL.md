# Technical Documentation

This document consolidates all technical implementation details, architecture, and guides.

## Table of Contents

1. [Architecture](#architecture)
2. [Module Structure](#module-structure)
3. [DLEQ Compatibility](#dleq-compatibility)
4. [Hash Function Analysis](#hash-function-analysis)
5. [MSM Hints Guide](#msm-hints-guide)
6. [Gas Benchmarks](#gas-benchmarks)

---

## Architecture

### Cryptographic Binding Strategy

**Problem**: Prove that the scalar `t` unlocking Starknet is identical to the scalar used in Monero's adaptor signature.

**Solution**: DLEQ proof binding:
- **Starknet domain**: `SHA-256(t) = H` (hashlock)
- **Monero domain**: `t · G = T` (adaptor point on Ed25519)
- **Proof**: DLEQ proves `∃t: SHA-256(t) = H ∧ t·G = T`

### Component Breakdown

```
Off-Chain (Rust) → On-Chain (Cairo + Garaga)
- Generate Monero scalar t
- Compute H = SHA-256(t)
- Compute T = t·G (Ed25519)
- Generate DLEQ proof π
- Serialize (H, T, π) for Cairo
```

### Gas Budget

| Operation | Estimated Gas | Notes |
|-----------|---------------|-------|
| SHA-256 (native) | ~50k | Constraint requirement |
| Ed25519 scalar mul (Garaga) | ~100-150k | Point verification |
| DLEQ verify (Garaga MSM) | ~250-350k | Binding proof |
| **Total per unlock** | **~300-400k** | **Acceptable** |

---

## Module Structure

### Cairo Modules

```
cairo/src/
├── lib.cairo              # Main AtomicLock contract
├── blake2s_challenge.cairo # BLAKE2s challenge computation
└── edwards_serialization.cairo # Edwards point serialization (placeholder)
```

### Key Functions

- `compute_dleq_challenge_blake2s()` - Computes DLEQ challenge using BLAKE2s
- `_verify_dleq_proof()` - Verifies DLEQ proof using Garaga MSM
- `decompress_edwards_pt_from_y_compressed_le_into_weirstrass_point()` - Point decompression

---

## DLEQ Compatibility

### Current Status

- ✅ **Cairo**: DLEQ verification implemented using BLAKE2s
- ✅ **Rust**: DLEQ proof generation implemented using BLAKE2s
- ✅ **Compatibility**: Hash functions aligned (both BLAKE2s)

### Implementation Details

**Rust** (`rust/src/dleq.rs`):
- Uses `blake2` crate for BLAKE2s
- Generates compressed Edwards points
- Computes challenge: `BLAKE2s("DLEQ" || G || Y || T || U || R1 || R2 || hashlock)`

**Cairo** (`cairo/src/blake2s_challenge.cairo`):
- Uses `core::blake` module for BLAKE2s
- Processes u256 values as u32 arrays
- Computes challenge: `BLAKE2s("DLEQ" || G || Y || T || U || R1 || R2 || hashlock)`

**Compatibility**: ✅ Verified - challenge computation matches between Rust and Cairo.

---

## Hash Function Analysis

### BLAKE2s vs Poseidon

| Hash Function | Challenge Gas | Total DLEQ Gas | Notes |
|---------------|---------------|----------------|-------|
| **BLAKE2s** | 50k-80k | 270k-440k | ✅ Current implementation |
| **Poseidon** | 400k-640k | 620k-1000k | ❌ Deprecated |

**Conclusion**: BLAKE2s provides 8x gas savings for challenge computation.

### Migration from Poseidon

**Status**: ✅ **COMPLETE**

- Migrated from Poseidon to BLAKE2s
- Updated challenge computation in `blake2s_challenge.cairo`
- Verified byte-order compatibility
- Tests pass with Rust test vectors

---

## MSM Hints Guide

### What Are MSM Hints?

Garaga's `msm_g1` function requires **fake-GLV hints** for efficient scalar multiplication. These hints are 10-felt arrays containing:
- Q.x limbs (4 felts): x-coordinate of result point Q = scalar * base_point
- Q.y limbs (4 felts): y-coordinate of result point Q
- s1 (1 felt): Scalar component for GLV decomposition
- s2_encoded (1 felt): Encoded scalar component

**Critical**: The hint Q **must equal** the actual result point for verification to pass.

### DLEQ Verification Requires 4 Hints

1. **s·G**: `s_hint_for_g` (Q = s·G)
2. **s·Y**: `s_hint_for_y` (Q = s·Y)
3. **(-c)·T**: `c_neg_hint_for_t` (Q = (-c)·T)
4. **(-c)·U**: `c_neg_hint_for_u` (Q = (-c)·U)

### Generating Hints

**Tool**: `tools/generate_hints_from_test_vectors.py`

```bash
cd tools
python3 generate_hints_from_test_vectors.py
```

**Output**: `cairo/test_hints.json` with all 4 hints in Cairo format.

---

## Gas Benchmarks

### DLEQ Verification Gas Costs

| Component | Gas Cost | Notes |
|-----------|----------|-------|
| BLAKE2s challenge | 50k-80k | 8x cheaper than Poseidon |
| MSM operations (4×) | 160k-240k | ~40k-60k per MSM |
| Point decompression (4×) | 40k-80k | ~10k-20k per point |
| Other operations | 20k-40k | Validation, storage, events |
| **Total** | **270k-440k** | **Production estimate** |

### Function Call Gas Costs

- `verify_and_unlock()`: 100k-200k gas
- `refund()`: 50k-150k gas
- `deposit()`: 50k-150k gas

### Optimization Opportunities

1. ✅ Batch MSM operations via `process_multiple_u256()`
2. ✅ Hint precomputation (already optimal)
3. ⚠️ Point caching (trade-off: storage vs computation)

---

## References

- Garaga v1.0.0: https://github.com/keep-starknet-strange/garaga
- BLAKE2s Specification (RFC 7693): https://www.rfc-editor.org/rfc/rfc7693
- Cairo Documentation: https://book.cairo-lang.org/

