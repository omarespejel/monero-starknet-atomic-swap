# DLEQ Proof Compatibility Guide

## Overview

This document describes the compatibility considerations between Rust (proof generation) and Cairo (proof verification) implementations of DLEQ proofs.

## Critical Compatibility Requirements

### 1. Second Generator Point Y

**Current Status:** Both Rust and Cairo use `2·G` as the second generator.

- **Rust:** `get_second_generator()` returns `ED25519_BASEPOINT_POINT * Scalar::from(2u64)`
- **Cairo:** `get_dleq_second_generator()` returns `ec_safe_add(G, G, ED25519_CURVE_INDEX)`

**Verification:** These implementations produce identical points.

**Future:** Once Python tool generates hash-to-curve constant, both will use:
- Hash-to-curve("DLEQ_SECOND_BASE_V1") → Edwards → Weierstrass → u384 limbs

---

### 2. Hash Function Compatibility ⚠️

**CRITICAL MISMATCH:** Rust and Cairo currently use different hash functions for challenge computation.

#### Current Implementation

**Rust (`rust/src/dleq.rs`):**
- Uses **SHA-256** for challenge computation
- Format: `H(tag || G || Y || T || U || R1 || R2 || hashlock)`
- Points serialized as compressed Edwards format (32 bytes each)
- Tag: Double SHA-256("DLEQ") for domain separation

**Cairo (`cairo/src/lib.cairo`):**
- Uses **Poseidon** for challenge computation (10x cheaper gas)
- Format: `H(tag || G || Y || T || U || R1 || R2 || hashlock)`
- Points serialized as u384 limbs (converted to felt252)
- Tag: `0x444c4551` ("DLEQ" as felt252) doubled

#### Impact

⚠️ **Proofs generated in Rust will NOT verify in Cairo** due to hash function mismatch.

#### Solutions

**Option A: Both use Poseidon (Recommended for Production)**
- ✅ 10x cheaper gas in Cairo
- ✅ More efficient for zkSTARKs
- ❌ Requires Rust Poseidon implementation
- **Action:** Add Poseidon crate to Rust, update `compute_challenge()`

**Option B: Both use SHA-256 (Simpler, Works Now)**
- ✅ Immediate compatibility
- ✅ Standard hash function
- ❌ Higher gas costs in Cairo
- **Action:** Revert Cairo to SHA-256 (previous implementation)

**Option C: Dual Support (Future)**
- Support both hash functions with a flag
- Allow migration path

---

## Recommended Next Steps

### Immediate (For Testing)

1. ✅ **Fixed:** Second generator uses `2·G` in both Rust and Cairo
2. ⚠️ **Pending:** Choose hash function strategy:
   - **Recommended:** Update Rust to use Poseidon
   - **Alternative:** Revert Cairo to SHA-256

### Production Path

1. Generate second generator constant using Python tool
2. Hardcode constant in both Rust and Cairo
3. Standardize on Poseidon for both (gas efficiency)
4. Add integration tests verifying Rust proof → Cairo verification

---

## Testing Compatibility

To verify Rust-Cairo compatibility:

```bash
# Generate proof in Rust
cargo run --bin maker

# Verify in Cairo test
scarb cairo-test --test test_dleq_rust_cairo_compatibility
```

---

## Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Second Generator (2·G) | ✅ Compatible | Both use 2·G |
| Hash Function | ⚠️ Mismatch | Rust: SHA-256, Cairo: Poseidon |
| Point Serialization | ⚠️ Different | Rust: Compressed Edwards, Cairo: u384 limbs |
| Challenge Format | ✅ Same | Both use Fiat-Shamir |
| Scalar Reduction | ✅ Compatible | Both reduce mod Ed25519 order |

---

## References

- [Garaga v1.0 Documentation](https://github.com/keep-starknet-strange/garaga)
- [DLEQ Specification](IMPLEMENTATION_SPEC.md)
- Rust Implementation: `rust/src/dleq.rs`
- Cairo Implementation: `cairo/src/lib.cairo`

