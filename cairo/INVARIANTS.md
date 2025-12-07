# Contract Invariants

This document describes the hard invariants enforced by the AtomicLock contract. These invariants are critical for security and must be maintained across all code changes.

## Constructor Invariants

These invariants are enforced during contract deployment:

1. **Hashlock Format**: `hash_words` must be exactly 8 u32 words (SHA-256 = 32 bytes = 8×u32)
2. **Adaptor Point Validation**: 
   - `adaptor_point` must be non-zero
   - `adaptor_point` must be on Ed25519 curve (verified via decompression)
   - `adaptor_point` must not be small-order (8-torsion subgroup)
3. **Timelock**: `lock_until > block.timestamp` (prevents immediate expiry)
4. **DLEQ Proof Verification**: DLEQ proof must verify (challenge matches computed)
   - Challenge: `c = BLAKE2s("DLEQ" || G || Y || T || U || R1 || R2 || hashlock) mod n`
   - Response: `s = k + c·t mod n`
   - Verification: `s·G - c·T = R1` and `s·Y - c·U = R2`
5. **Fake-GLV Hint Validation**:
   - Hint must be exactly 10 felts: `[Q.x[4], Q.y[4], s1, s2]`
   - Q must match adaptor point
   - s1 and s2 must be non-zero
6. **Token/Amount Consistency**: 
   - Both `token` and `amount` must be zero (testing) OR both non-zero (production)
   - Cannot have non-zero token with zero amount or vice versa

## State Invariants

These invariants hold throughout the contract's lifetime:

1. **Unlock Irreversibility**: Once `unlocked == true`, it cannot become `false`
2. **Mutual Exclusivity**: `refund()` and `verify_and_unlock()` are mutually exclusive
   - If unlocked, refund cannot be called
   - If refunded, unlock cannot be called
3. **Token Balance**: After successful unlock or refund, contract token balance equals zero
4. **Timelock Enforcement**: Refund can only be called after `lock_until` timestamp

## Cryptographic Invariants

These invariants are enforced by the cryptographic verification:

1. **Challenge Computation**: 
   ```
   c = BLAKE2s("DLEQ" || G || Y || T || U || R1 || R2 || hashlock) mod n
   ```
   - Uses RFC 7693 compliant BLAKE2s initialization vector
   - Hashlock words are byte-swapped (big-endian → little-endian) before hashing
   - Challenge is reduced modulo Ed25519 order

2. **DLEQ Verification** (4 MSM operations):
   - `s·G - c·T = R1` (using `s_hint_for_g` and `c_neg_hint_for_t`)
   - `s·Y - c·U = R2` (using `s_hint_for_y` and `c_neg_hint_for_u`)
   - All MSM operations use Garaga's fake-GLV optimization
   - All points must decompress successfully (on-curve validation)

3. **Scalar Reduction**:
   - Challenge and response are truncated to 128 bits before use
   - `reduce_felt_to_scalar(felt252) -> u256 { low: as_u256.low, high: 0 }`
   - Scalar must be non-zero and less than Ed25519 order

4. **Point Validation**:
   - All points (T, U, R1, R2) must decompress successfully
   - All points must not be small-order (8-torsion subgroup)
   - Base points G and Y are hardcoded constants (RFC 8032 compliant)

## Runtime Invariants

These invariants are enforced during contract execution:

1. **verify_and_unlock**:
   - Secret must hash to stored hashlock: `SHA-256(secret) == hashlock`
   - Contract must not already be unlocked
   - MSM verification must succeed (adaptor scalar extraction)

2. **refund**:
   - Caller must be the depositor
   - `block.timestamp >= lock_until`
   - Contract must still be locked (`unlocked == false`)

3. **deposit**:
   - Token transfer must succeed (requires prior approval)
   - Amount must match constructor `amount` parameter

## Security Invariants

1. **Reentrancy Protection**: OpenZeppelin ReentrancyGuard prevents reentrancy attacks
2. **Small-Order Point Rejection**: All adaptor points are checked against 8-torsion subgroup
3. **Zero Scalar Rejection**: Challenge and response scalars cannot be zero
4. **Hint Validation**: All fake-GLV hints are validated before MSM operations

## Testing Invariants

When writing tests, ensure:

1. **Test Isolation**: Each test deploys a fresh contract instance
2. **State Verification**: After each operation, verify contract state matches expectations
3. **Error Testing**: All error paths are tested with `#[should_panic]`
4. **Edge Cases**: Boundary values (max scalars, zero, order-1) are tested

## Violation Consequences

Violating any invariant will cause:
- **Constructor**: Deployment fails (transaction reverts)
- **Runtime**: Function call fails (transaction reverts)
- **Security**: Potential vulnerability (requires immediate fix)

## Maintenance

When modifying the contract:
1. Review all affected invariants
2. Update this document if invariants change
3. Add tests for new invariants
4. Verify existing tests still pass

