# Protocol Mismatch Analysis: Adaptor Point vs Scalar Derivation

## Issue Identified

There is a **fundamental protocol mismatch** between how the adaptor point is generated and how the scalar is derived in the contract.

### Current Implementation

**Rust (Adaptor Point Generation)**:
```rust
// From rust/src/bin/generate_test_vector.rs
let secret = Scalar::from_bytes_mod_order(secret_bytes);
let T = ED25519_BASEPOINT_POINT * secret;  // adaptor_point = secret·G
```

**Cairo (Scalar Derivation)**:
```cairo
// From cairo/src/lib.cairo:588-589
let mut scalar = hash_to_scalar_u256(h0, h1, h2, h3, h4, h5, h6, h7);
scalar = reduce_scalar_ed25519(scalar);
// Where [h0...h7] = SHA-256(secret)
```

**Cairo (MSM Verification)**:
```cairo
// Line 594-600
let computed = msm_g1([G], [scalar], ...);
assert(computed == adaptor_point, 'MSM verification failed');
```

### The Problem

1. **Adaptor point**: `T = secret·G` (generated from secret directly)
2. **Contract scalar**: `scalar = hash_to_scalar_u256(SHA-256(secret))` (derived from hashlock)
3. **Verification**: `scalar·G == adaptor_point`
4. **Mismatch**: `hash_to_scalar_u256(SHA-256(secret))·G != secret·G` (unless SHA-256(secret) == secret, which is extremely unlikely)

### Mathematical Verification

From test vectors:
- Secret: `0x1212121212121212121212121212121212121212121212121212121212121212`
- Secret scalar: `0x2121212121212121212121212121211fd3318336f1a753bb9ffaef7b51c3e25`
- Hashlock: `SHA-256(secret) = 0xd78e3502108c5b5a5c902f24725ce15e14ab8e411b93285f9c5b1405f11dca4d`
- Hashlock scalar: `0x0dca1df105145b9c5f28931b418eab140b6574f798511d02fa11ffa68e5e3f23`

**Result**:
- `secret_scalar·G` ≠ `hashlock_scalar·G`
- Therefore: `hashlock_scalar·G != adaptor_point` (which is `secret_scalar·G`)

## Protocol Design Question

The README states:
> "DLEQ proofs bind hashlock (H) and adaptor point (T) by proving ∃t: SHA-256(t) = H ∧ t·G = T"

This means there exists a scalar `t` such that:
- `SHA-256(t) = H` (hashlock)
- `t·G = T` (adaptor point)

So `t` is the secret, and the contract should verify `t·G == T` where `t` is the revealed secret.

## Possible Solutions

### Option 1: Use Secret Directly (RECOMMENDED)

**Change contract to use secret scalar directly**:
```cairo
// Instead of:
let scalar = hash_to_scalar_u256(h0, h1, h2, h3, h4, h5, h6, h7);

// Use:
let scalar = secret_to_scalar_u256(secret_bytes);
```

**Pros**:
- Matches Rust implementation
- Matches protocol specification
- Simpler and more direct

**Cons**:
- Requires changing contract logic
- Need to add `secret_to_scalar_u256` function

### Option 2: Generate Adaptor Point from Hashlock Scalar

**Change Rust to generate adaptor point from hashlock scalar**:
```rust
// Instead of:
let T = ED25519_BASEPOINT_POINT * secret;

// Use:
let hashlock_scalar = hash_to_scalar_u256(SHA-256(secret));
let T = ED25519_BASEPOINT_POINT * hashlock_scalar;
```

**Pros**:
- No contract changes needed
- Keeps current contract logic

**Cons**:
- Changes Rust implementation
- May affect Monero-side adaptor signature generation
- Less intuitive (adaptor point from hashlock, not secret)

### Option 3: Verify Both Relationships

**Verify both**:
1. `SHA-256(secret) == hashlock` (already verified)
2. `secret·G == adaptor_point` (new verification)

**Pros**:
- Most secure (verifies both relationships)
- Matches protocol specification exactly

**Cons**:
- Requires contract changes
- More complex verification

## Current Status

- ✅ Hint Q coordinates: Correct (match adaptor_point from secret·G)
- ✅ s1/s2 decomposition: Correct (for secret scalar)
- ❌ Contract scalar derivation: Uses hashlock scalar (mismatch)
- ❌ MSM verification: Will fail because `hashlock_scalar·G != secret·G`

## Recommendation

**Use Option 1**: Change contract to use secret scalar directly. This:
1. Matches the protocol specification
2. Matches Rust implementation
3. Is the most intuitive approach
4. Requires minimal changes (add `secret_to_scalar_u256` function)

## Next Steps

1. **Immediate**: Document this issue for auditor review
2. **Short-term**: Decide on solution (Option 1, 2, or 3)
3. **Implementation**: Apply chosen solution
4. **Testing**: Verify end-to-end test passes

