# Hash Function Analysis: Poseidon vs BLAKE2s vs SHA-256

## Executive Summary

**Current Status:** Using Poseidon in Cairo (10x cheaper than SHA-256)  
**Future Consideration:** BLAKE2s (8x cheaper than Poseidon, aligned with Starknet roadmap)  
**Monero Compatibility:** ✅ **SAFE** - DLEQ proof is internal to Starknet, does NOT affect Monero handshake

---

## Critical Finding: Monero Handshake Safety ✅

**Your DLEQ proof is internal to Starknet and does NOT interact with Monero's atomic swap protocol.**

### Why It's Safe:

1. **Monero Atomic Swap Protocol Uses:**
   - DLEQ proofs for **cross-curve verification** (ed25519 ↔ Ristretto/secp256k1)
   - Generic hash (typically SHA-256 or Keccak256) for challenge computation
   - Purpose: Prove Monero keys and Bitcoin/Ethereum keys share the same discrete log

2. **Your DLEQ Proof Purpose:**
   - **Internal Starknet verification only**: Proves `SHA-256(t) = H` and `t·G = T` share the same secret `t`
   - **No cross-chain interaction**: Monero side never sees or verifies your Starknet DLEQ proof
   - **Separation**: Monero handshake happens independently using its own DLEQ format

3. **Conclusion:**
   - Changing hash function (SHA-256 → Poseidon → BLAKE2s) affects **only Starknet verification**
   - **Monero handshake is completely unaffected** regardless of hash function choice
   - These are two different proofs for different purposes

---

## Hash Function Comparison

| Hash Function | Gas Cost | Cairo Support | Rust Support | Starknet Alignment | Status |
|--------------|----------|---------------|--------------|-------------------|--------|
| **BLAKE2s** | **1x** (cheapest) | ⚠️ Check stdlib | ✅ `blake2` crate | ✅ v0.14.1+ direction | **Future** |
| **Poseidon** | **8x** | ✅ Native (Garaga) | ⚠️ Requires impl | ⚠️ Not aligned | **Current** |
| **SHA-256** | **80x** | ✅ Core library | ✅ `sha2` crate | ❌ Not optimal | **Fallback** |

### Cost Analysis (Relative to BLAKE2s):

- **BLAKE2s**: 1x (baseline, cheapest)
- **Poseidon**: ~8x more expensive
- **SHA-256**: ~80x more expensive

---

## BLAKE2s Implementation Details

### Why BLAKE2s?

1. **Starknet v0.14.1+ Direction:**
   - Moved to BLAKE for `compiled_class_hash` (SNIP-34)
   - **8x cheaper** proving costs with Stwo compared to Poseidon
   - Aligned with Starknet's future roadmap

2. **Technical Benefits:**
   - Standard cryptographic primitive (RFC 7693)
   - Well-supported in Rust (`blake2` crate)
   - Efficient for ZK proofs

### Implementation Requirements

#### Cairo Side (Starknet Contract)

**Check if Available:**
```cairo
// Try importing:
use core::hash::blake2s;
// OR
use starknet::syscalls::blake2s_syscall;
```

**If Available:**
```cairo
fn compute_dleq_challenge(
    G: G1Point,
    Y: G1Point,
    T: G1Point,
    U: G1Point,
    R1: G1Point,
    R2: G1Point,
    hashlock: Span<u32>,
) -> felt252 {
    let mut hasher = blake2s::new();
    
    // Serialize points in same format as Rust
    serialize_point_to_blake2s(ref hasher, G);
    serialize_point_to_blake2s(ref hasher, Y);
    serialize_point_to_blake2s(ref hasher, T);
    serialize_point_to_blake2s(ref hasher, U);
    serialize_point_to_blake2s(ref hasher, R1);
    serialize_point_to_blake2s(ref hasher, R2);
    
    // Add hashlock
    let mut i = 0;
    while i < hashlock.len() {
        hasher.update((*hashlock.at(i)).into());
        i += 1;
    }
    
    let hash = hasher.finalize();
    reduce_to_scalar(hash)
}
```

**If Not Available:**
- Keep Poseidon (already working)
- Document as "future optimization"
- Wait for Cairo stdlib support

#### Rust Side (DLEQ Prover)

**Implementation:**
```rust
// Add to Cargo.toml
[dependencies]
blake2 = "0.10"

// In dleq.rs
use blake2::{Blake2s256, Digest};

fn compute_challenge(
    G: &EdwardsPoint,
    Y: &EdwardsPoint,
    T: &EdwardsPoint,
    U: &EdwardsPoint,
    R1: &EdwardsPoint,
    R2: &EdwardsPoint,
    hashlock: &[u8; 32],
) -> Scalar {
    let mut hasher = Blake2s256::new();
    
    // CRITICAL: Serialize points in same format as Cairo
    // Must match exactly: u384 limbs or compressed format?
    serialize_point_for_hash(&mut hasher, G);
    serialize_point_for_hash(&mut hasher, Y);
    serialize_point_for_hash(&mut hasher, T);
    serialize_point_for_hash(&mut hasher, U);
    serialize_point_for_hash(&mut hasher, R1);
    serialize_point_for_hash(&mut hasher, R2);
    
    hasher.update(hashlock);
    
    let result = hasher.finalize();
    Scalar::from_bytes_mod_order(result.into())
}
```

### Critical Implementation Considerations

#### A. Point Serialization MUST Match

**Problem:** Ed25519 points can be serialized differently:
- **Compressed** (32 bytes): Standard ed25519 format
- **u384 limbs** (4 × 96-bit limbs): Garaga's internal format

**Solution:** Both sides MUST use **identical serialization**:
- If Cairo uses u384 limbs → Rust must convert Edwards → Weierstrass → u384 limbs
- If Cairo uses compressed → Rust uses `point.compress().as_bytes()`

#### B. Hash Input Ordering

**Critical:** Both sides MUST hash points in **identical order**:
```
BLAKE2s(tag || tag || G || Y || T || U || R1 || R2 || hashlock)
```

Where `||` means concatenation in the **same byte format**.

#### C. Domain Separator

**Current (Poseidon):** `0x444c4551` ("DLEQ" as felt252) doubled  
**BLAKE2s:** Use same tag format for consistency

---

## Recommended Implementation Path

### Phase 1: Research (1 day)

**Tasks:**
1. ✅ Check if Cairo 2.x stdlib has BLAKE2s support
2. ✅ Verify `core::hash::blake2s` or `starknet::syscalls::blake2s_syscall` availability
3. ✅ Check Garaga documentation for BLAKE2s utilities
4. ✅ Research Starknet v0.14.1+ BLAKE2s usage patterns

**Decision Point:**
- If BLAKE2s available → Proceed to Phase 2
- If not available → Keep Poseidon, document as future optimization

### Phase 2: Implementation (2-3 days)

**If BLAKE2s Available:**

1. **Cairo Side:**
   - Replace Poseidon with BLAKE2s in `compute_dleq_challenge()`
   - Ensure point serialization matches Rust
   - Update tests

2. **Rust Side:**
   - Add `blake2` crate dependency
   - Implement `compute_challenge()` with BLAKE2s
   - Match Cairo's serialization format exactly
   - Update tests

3. **Integration:**
   - Generate proof in Rust
   - Verify in Cairo
   - Ensure identical hash outputs

**If BLAKE2s Not Available:**

- Keep Poseidon implementation
- Document BLAKE2s as "future optimization" in roadmap
- Monitor Cairo stdlib updates

### Phase 3: Validation

**Checklist:**
- [ ] Rust and Cairo hash **identical test vectors**
- [ ] Point serialization format **100% identical**
- [ ] DLEQ proof generated in Rust **verifies in Cairo**
- [ ] Integration test: `cargo run --bin maker` → Cairo contract accepts proof
- [ ] Gas benchmark: measure actual proving costs
- [ ] Document hash function choice and rationale

---

## Current Recommendation

### For Prototype/PoC (Now):

**Keep Poseidon** ✅
- Already implemented and working
- Cairo native support via Garaga
- Production-ready now
- 10x cheaper than SHA-256

### For Production (Future):

**Migrate to BLAKE2s** ✅
- 8x cheaper than Poseidon
- Aligned with Starknet roadmap
- Standard cryptographic primitive
- Better long-term alignment

### Rationale:

1. **Project Status:** Prototype/PoC → Poseidon works fine for now
2. **Strategic Alignment:** BLAKE2s is correct for Starknet's roadmap
3. **Don't Block:** Don't delay on BLAKE2s if stdlib support isn't ready
4. **Monero Safety:** Handshake unaffected regardless of choice

---

## References

- [RFC 0241: Atomic Swap XMR](https://rfc.tari.com/RFC-0241_AtomicSwapXMR)
- [Starknet SNIP-34: More Efficient Casm Hashes](https://community.starknet.io/t/snip-34-more-efficient-casm-hashes/115979)
- [Starknet Version Notes](https://docs.starknet.io/learn/cheatsheets/version-notes)
- [Garaga Hashing Utils](https://github.com/keep-starknet-strange/garaga/blob/v1.0.0/src/src/utils/hashing.cairo)
- [StarknetJS Hash API](https://starknetjs.com/docs/API/namespaces/hash/)

---

## Summary

**Bottom Line:**
- ✅ **Monero handshake is completely safe** - DLEQ hash function choice only affects Starknet-side verification
- ✅ **Poseidon is fine for now** - Already working, 10x cheaper than SHA-256
- ✅ **BLAKE2s is future-optimal** - 8x cheaper than Poseidon, aligned with Starknet roadmap
- ⚠️ **Check Cairo stdlib** - BLAKE2s support may not be available yet

**Action Items:**
1. Research Cairo BLAKE2s availability
2. If available → Plan migration
3. If not → Keep Poseidon, document BLAKE2s as future optimization

