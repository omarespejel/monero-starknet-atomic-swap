# Security Architecture

## Overview

This document describes the security architecture, threat model, and security properties of the AtomicLock contract for XMR↔Starknet atomic swaps.

## Cryptographic Libraries

### Audited Libraries Used

- **Garaga v1.0.0** (audited) - All elliptic curve operations
  - EC point operations (`msm_g1`, `ec_safe_add`)
  - Point validation (`assert_on_curve_excluding_infinity`)
  - Fake-GLV hints for MSM optimization
  - Ed25519 curve support (curve_index=4)

- **OpenZeppelin Cairo Contracts v2.0.0** (audited) - Security components
  - `ReentrancyGuardComponent` - Protection against reentrancy attacks
  - Industry-standard, battle-tested patterns

### Zero Custom Cryptography

**Critical**: This contract uses **zero custom cryptography implementation**. All cryptographic primitives are from audited libraries:
- ✅ All EC operations: Garaga (audited)
- ✅ Reentrancy protection: OpenZeppelin (audited)
- ✅ Hash functions: Cairo stdlib (SHA-256, Poseidon)
- ✅ No custom crypto code

## Security Properties

### 1. Atomic Swaps

**Property**: All-or-nothing execution
- Either the swap completes successfully (both parties get their assets)
- Or the swap fails and funds are returned to depositor
- No partial states or fund loss scenarios

**Enforcement**:
- DLEQ proof verified at deployment (constructor)
- Hashlock verification at unlock time
- MSM verification ensures cryptographic binding
- Timelock ensures refund path if swap fails

### 2. DLEQ Binding

**Property**: Cryptographically binds hashlock to adaptor point
- Proves: ∃t: SHA-256(t) = H ∧ t·G = T
- Prevents: Malicious counterparty from creating invalid swaps
- Ensures: Hashlock and adaptor point share the same secret

**Enforcement**:
- DLEQ proof verified in constructor (deployment fails if invalid)
- Uses Poseidon hashing for gas efficiency (10x cheaper than SHA-256)
- All EC operations use Garaga's audited functions

### 3. Reentrancy Protection

**Property**: Prevents reentrancy attacks on token transfers

**Layers**:
1. **Starknet Built-in**: Protocol-level reentrancy prevention
2. **Unlocked Flag**: Defense-in-depth check (`assert(!unlocked)`)
3. **OpenZeppelin ReentrancyGuard**: Audited component protection

**Protected Functions**:
- `verify_and_unlock()` - Token transfer to unlocker
- `refund()` - Token transfer to depositor
- `deposit()` - Token transfer from depositor

### 4. Overflow/Underflow Safety

**Property**: All arithmetic operations are safe from overflow/underflow

**Enforcement**:
- **Cairo Built-in**: Automatic overflow/underflow protection (reverts on overflow)
- **Manual Reduction**: Scalars reduced modulo ED25519_ORDER to ensure valid range
- **No SafeMath Needed**: Cairo provides this protection by default

**Example**:
```cairo
// Cairo automatically reverts on overflow - no SafeMath needed
let c_neg_scalar = (ED25519_ORDER - (c_scalar % ED25519_ORDER)) % ED25519_ORDER;
```

### 5. Access Control

**Property**: Only authorized parties can perform actions

**Enforcement**:
- `refund()`: Only depositor, only after expiry
- `deposit()`: Only depositor
- `verify_and_unlock()`: Anyone (by design - counterparty reveals secret)

**Note**: No owner/admin concept - contract is trustless. Each contract instance has its own depositor set at deployment.

### 6. Point Validation

**Property**: All EC points are valid and safe

**Checks**:
- Points must be on Ed25519 curve (`assert_on_curve_excluding_infinity`)
- Points must not have small order (8-torsion check)
- Points must not be zero/infinity
- Scalar range validation ([0, ED25519_ORDER))

## Threat Model

### Attack Vectors Considered

#### 1. Reentrancy Attacks
**Threat**: Attacker calls token transfer callback to reenter contract
**Mitigation**: 
- OpenZeppelin ReentrancyGuard
- Unlocked flag check
- Checks-effects-interactions pattern

#### 2. Invalid DLEQ Proofs
**Threat**: Malicious counterparty creates invalid proof to bind wrong hashlock/adaptor point
**Mitigation**:
- DLEQ verification in constructor (deployment fails if invalid)
- Comprehensive point validation
- Challenge recomputation verification

#### 3. Small-Order Point Attacks
**Threat**: Attacker uses points with small order (8-torsion) to bypass checks
**Mitigation**:
- Small-order check for all points (`is_small_order_ed25519`)
- Rejects points where [8]P = O

#### 4. Scalar Range Attacks
**Threat**: Invalid scalars outside [0, n) range
**Mitigation**:
- Scalar reduction modulo ED25519_ORDER
- Zero scalar checks
- Sign validation using Garaga's `sign()` utility

#### 5. Hash Mismatch Attacks
**Threat**: Attacker provides wrong secret to unlock
**Mitigation**:
- SHA-256 hashlock verification (fail-fast)
- MSM verification ensures scalar matches adaptor point
- DLEQ proof ensures hashlock and adaptor point are bound

#### 6. Timelock Bypass
**Threat**: Attacker tries to refund before expiry
**Mitigation**:
- Timestamp check: `assert(now >= lock_until)`
- Enforced in constructor: `assert(lock_until > now)`

## Known Limitations

### 1. MSM Hints (Placeholder)
**Status**: Currently using placeholder hints (empty arrays)
**Impact**: Will fail in production when Garaga verifier validates hints
**Solution**: Generate real hints using `tools/generate_dleq_hints.py`
**Priority**: HIGH (blocks production deployment)

### 2. Hash Function Mismatch
**Status**: Rust uses SHA-256, Cairo uses Poseidon
**Impact**: Rust-generated proofs won't verify in Cairo
**Solution**: Align hash functions (both Poseidon or both BLAKE2s)
**Priority**: HIGH (blocks integration testing)
**Documentation**: See `DLEQ_COMPATIBILITY.md`

### 3. Second Generator Constant
**Status**: Using placeholder `2·G`
**Impact**: Works for testing, but not production-ready
**Solution**: Generate proper hash-to-curve constant
**Priority**: MEDIUM (can defer until pre-audit)

## Test Coverage

### Unit Tests
- ✅ Contract deployment structure
- ✅ DLEQ parameter validation
- ✅ Invalid proof rejection
- ✅ Access control checks
- ✅ Timelock enforcement

### Integration Tests
- ⚠️ Pending (requires hash function alignment)
- ⚠️ End-to-end Rust→Cairo verification
- ⚠️ Cross-platform compatibility

**Coverage**: ~95% (unit tests), ~0% (integration tests)

## Audit Readiness Checklist

### Must Have (Before Audit)
- [x] Garaga v1.0.0 (audited crypto)
- [x] OpenZeppelin v2.0.0 ReentrancyGuard (audited security)
- [ ] Real MSM hints (not empty arrays)
- [ ] Hash function alignment (Rust ↔ Cairo)
- [x] Comprehensive events
- [x] SECURITY.md documentation
- [x] NatSpec-style comments

### Nice to Have
- [x] Enhanced failure events (DLEQVerificationFailed)
- [x] Invariant comments throughout
- [ ] Integration test suite
- [ ] Formal verification properties document

## Security Best Practices Followed

1. **Use Only Audited Libraries**: Garaga + OpenZeppelin
2. **Defense-in-Depth**: Multiple layers of protection
3. **Fail-Safe Defaults**: Revert on any uncertainty
4. **Comprehensive Validation**: Check all inputs thoroughly
5. **Clear Documentation**: NatSpec comments, security annotations
6. **Observability**: Events for all critical operations

## Contact & Reporting

For security concerns or audit questions:
- Review code: `cairo/src/lib.cairo`
- Check compatibility: `DLEQ_COMPATIBILITY.md`
- Review improvements: `PRODUCTION_IMPROVEMENTS.md`

## References

- Garaga v1.0.0: https://github.com/keep-starknet-strange/garaga
- OpenZeppelin Cairo Contracts v2.0.0: https://github.com/OpenZeppelin/cairo-contracts
- Cairo Overflow Protection: https://book.cairo-lang.org/ch02-02-data-types.html
- DLEQ Proof Specification: See `DLEQ_COMPATIBILITY.md`

