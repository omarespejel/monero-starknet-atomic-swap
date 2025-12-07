# Security Auditor's Guide

This document provides guidance for security auditors reviewing the Monero-Starknet atomic swap protocol implementation.

## Quick Start

### Repository Structure

- `rust/`: Rust library (key splitting, DLEQ proofs)
- `cairo/`: Starknet contract (AtomicLock, DLEQ verification)
- `tools/`: Python utilities (hint generation, verification)
- `docs/`: Documentation (architecture, protocol, decisions)

### Key Files for Review

**Rust Cryptography**:
- `rust/src/monero/key_splitting.rs`: Key splitting implementation
- `rust/src/dleq.rs`: DLEQ proof generation
- `rust/tests/dleq_properties.rs`: Property-based tests

**Cairo Contract**:
- `cairo/src/lib.cairo`: AtomicLock contract
- `cairo/src/blake2s_challenge.cairo`: Challenge computation
- `cairo/tests/security/`: Security test suite

**Security Documentation**:
- `SECURITY.md`: Comprehensive security analysis
- `KEY_SPLITTING_SECURITY_ANALYSIS.md`: Key splitting deep dive
- `RACE_CONDITION_MITIGATION.md`: Known vulnerability and fixes

## Security Properties to Verify

### 1. Key Splitting Security

Verify that:
- `x_partial` and `t` are statistically independent
- No information leakage from `T = t·G`
- Timing attacks are mitigated (constant-time operations)
- Memory safety (zeroization)

**Test**: `rust/tests/dleq_properties.rs` - Property-based tests

### 2. DLEQ Proof Security

Verify that:
- Nonce generation is deterministic and domain-separated
- Challenge computation matches between Rust and Cairo
- Input validation prevents invalid proofs
- Proof structure is cryptographically sound

**Test**: `cairo/tests/security/dleq_negative.cairo` - Negative tests

### 3. Contract Security

Verify that:
- Reentrancy protection (three layers)
- Point validation (on-curve, small-order checks)
- Access control (depositor-only operations)
- Overflow/underflow safety (Cairo built-in)

**Test**: `cairo/tests/security/audit.cairo` - Security audit tests

### 4. Cross-Chain Race Condition

**Known Issue**: Race condition between secret revelation and cross-chain confirmation.

**Status**: Documented, mitigations planned for v0.8.0

**See**: `RACE_CONDITION_MITIGATION.md` for details

## Cryptographic Libraries Used

All cryptographic operations use audited libraries:

| Library | Version | Audit Status |
|---------|---------|--------------|
| curve25519-dalek | 4.1 | Quarkslab 2019 |
| Garaga | 1.0.1 | Audited |
| OpenZeppelin | 2.0.0 | Audited |
| blake2 | 0.10 | RustCrypto (widely reviewed) |

**Zero Custom Cryptography**: No custom cryptographic primitives implemented.

## Test Coverage

### Rust Tests

- 32 tests total
- Property-based tests for cryptographic properties
- Integration tests for key splitting + DLEQ
- End-to-end atomic swap tests

### Cairo Tests

- 107 tests total
- Security tests: 9/9 passing
- End-to-end tests: Rust-Cairo compatibility verified
- Unit tests: Individual component verification

## Known Vulnerabilities

### Race Condition (Protocol-Level)

**Severity**: Critical for production

**Status**: Documented, mitigations planned

**Mitigation**: Two-phase unlock with grace period (planned for v0.8.0)

**See**: `RACE_CONDITION_MITIGATION.md`

## Areas Requiring Special Attention

### 1. Nonce Generation

Verify domain separation and non-zero validation:
- `rust/src/dleq.rs`: `generate_deterministic_nonce()`
- Uses `b"DLEQ_NONCE_V1"` prefix
- Counter-based retry if nonce is zero

### 2. Challenge Computation

Verify Rust-Cairo compatibility:
- `rust/src/dleq.rs`: `compute_challenge()`
- `cairo/src/blake2s_challenge.cairo`: `compute_dleq_challenge_blake2s()`
- Both use BLAKE2s with identical format

### 3. Point Validation

Verify all points are validated:
- `cairo/src/lib.cairo`: Constructor validates all DLEQ points
- On-curve checks: `assert_on_curve_excluding_infinity()`
- Small-order checks: `is_small_order_ed25519()`

### 4. Memory Safety

Verify zeroization:
- `rust/src/monero/key_splitting.rs`: `SwapKeyPair` derives `Zeroize`
- `rust/src/dleq.rs`: Nonces wrapped in `Zeroizing<Scalar>`
- All secrets automatically zeroed when dropped

## Running Tests

```bash
# Rust tests
cd rust && cargo test

# Cairo security tests
cd cairo && snforge test security -v

# Cairo E2E tests
cd cairo && snforge test e2e -v

# Cross-platform verification
python tools/verify/rust_cairo_compatibility.py
```

## Questions for Auditors

1. Is the key splitting approach secure given the DLP assumption?
2. Are there any timing side-channels in the implementation?
3. Is the DLEQ proof structure cryptographically sound?
4. Are all edge cases handled (zero scalars, small-order points)?
5. Is the race condition mitigation plan sufficient?
6. Are there any other protocol-level vulnerabilities?

## References

- Serai DEX (audited pattern): https://github.com/serai-dex/serai
- Quarkslab Audit: https://blog.quarkslab.com/security-audit-of-dalek-libraries.html
- BLAKE2 Specification: https://www.rfc-editor.org/rfc/rfc7693
- Ed25519 Specification: https://www.rfc-editor.org/rfc/rfc8032

---

**Version**: 0.7.1-alpha  
**Last Updated**: 2025-12-07

