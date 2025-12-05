# Poseidon Implementation Plan

## Current Status

**Cairo:** ✅ Uses Poseidon (10x cheaper gas)  
**Rust:** ⚠️ Uses SHA-256 (incompatible with Cairo)

## The Challenge

To match Cairo's Poseidon implementation exactly, we need:

1. **Edwards → Weierstrass Conversion**
   - Rust uses Edwards coordinates (curve25519-dalek)
   - Cairo uses Weierstrass coordinates (Garaga curve_index=4)
   - Need birational map conversion

2. **u384 Limb Extraction**
   - Cairo stores Weierstrass coordinates as u384 (4×96-bit limbs)
   - Need to extract limbs: `[x.limb0, x.limb1, x.limb2, x.limb3, y.limb0, y.limb1, y.limb2, y.limb3]`

3. **Poseidon Hash Implementation**
   - Must match Cairo's `core::poseidon::PoseidonTrait` exactly
   - Uses Hades permutation with sponge construction
   - 3-element state (s0, s1, s2)

## Implementation Options

### Option A: Full Poseidon Implementation (Recommended)

**Steps:**
1. Add `poseidon-rs` or similar Starknet-compatible Poseidon crate
2. Implement Edwards → Weierstrass conversion
3. Extract u384 limbs from Weierstrass coordinates
4. Hash limbs using Poseidon (matching Cairo format)

**Pros:**
- ✅ Full compatibility with Cairo
- ✅ 10x gas savings
- ✅ Production-ready

**Cons:**
- ❌ Complex Edwards→Weierstrass conversion
- ❌ Requires careful limb extraction
- ❌ More implementation time

### Option B: Use Existing Python Tool

**Steps:**
1. Use `tools/generate_ed25519_test_data.py` to convert Edwards → Weierstrass
2. Extract u384 limbs in Python
3. Pass limbs to Rust for Poseidon hashing
4. Or: Generate test vectors in Python, verify in Rust

**Pros:**
- ✅ Reuses existing tooling
- ✅ Faster to implement
- ✅ Can generate test vectors

**Cons:**
- ❌ Requires Python dependency
- ❌ Less elegant than pure Rust

### Option C: Keep SHA-256 (Simpler)

**Steps:**
1. Revert Cairo to SHA-256
2. Keep Rust SHA-256
3. Document gas trade-off

**Pros:**
- ✅ Immediate compatibility
- ✅ Simpler implementation
- ✅ Works now

**Cons:**
- ❌ Lose 10x gas savings
- ❌ Not optimal for production

## Recommended Path

**Phase 1: Immediate (Testing)**
- Keep SHA-256 in both (revert Cairo)
- Get tests passing
- Verify end-to-end flow

**Phase 2: Production (Gas Optimization)**
- Implement full Poseidon in Rust
- Use Python tool for Edwards→Weierstrass conversion initially
- Gradually move to pure Rust implementation

## Technical Details

### Cairo's Poseidon Format

```cairo
// Tag: 0x444c4551 ("DLEQ" as felt252)
state = state.update(0x444c4551);
state = state.update(0x444c4551);

// Points: 8 felt252 values per point (u384 limbs)
// Format: x.limb0, x.limb1, x.limb2, x.limb3, y.limb0, y.limb1, y.limb2, y.limb3
state = serialize_point_to_poseidon(state, G);
state = serialize_point_to_poseidon(state, Y);
// ... etc

// Hashlock: 8 u32 words
for word in hashlock {
    state = state.update(word.into());
}

// Finalize
let hash_felt = state.finalize();
```

### Required Rust Implementation

```rust
// 1. Convert Edwards → Weierstrass
let weierstrass_point = edwards_to_weierstrass(edwards_point);

// 2. Extract u384 limbs
let limbs = extract_u384_limbs(weierstrass_point);
// Returns: [x.limb0, x.limb1, x.limb2, x.limb3, y.limb0, y.limb1, y.limb2, y.limb3]

// 3. Hash with Poseidon
let mut state = PoseidonState::new();
state = state.update(0x444c4551); // "DLEQ" tag
state = state.update(0x444c4551);
for limb in limbs {
    state = state.update(limb);
}
let hash = state.finalize();
```

## References

- [Cairo Poseidon Documentation](https://docs.starknet.io/build/corelib/core-poseidon-HashState)
- [Garaga u384 Format](https://github.com/keep-starknet-strange/garaga)
- [Edwards to Weierstrass Conversion](https://en.wikipedia.org/wiki/Edwards_curve)

## Next Steps

1. ✅ Created `rust/src/poseidon.rs` placeholder
2. ⏳ Implement Edwards → Weierstrass conversion
3. ⏳ Extract u384 limbs
4. ⏳ Add Poseidon hash library
5. ⏳ Update `compute_challenge()` to use Poseidon
6. ⏳ Add integration tests

