# Cryptographic Dependencies Audit Status

This document tracks the audit status of all cryptographic dependencies used in the project.

## Rust Side

### Core Cryptography

- [x] **curve25519-dalek 4.1.x** - Quarkslab audited (2023)
  - Used for: Ed25519 point/scalar operations
  - Source: [crates.io](https://crates.io/crates/curve25519-dalek)
  - Audit: Quarkslab security audit

- [x] **monero-clsag-mirror 0.1** - ⚠️ TEMPORARY: Unofficial mirror (same code)
  - Used for: CLSAG ring signatures, key images, transaction signing
  - Source: [crates.io](https://crates.io/crates/monero-clsag-mirror) (unofficial mirror by sneurlax)
  - **Target**: Use git source when available: `monero-clsag = { git = "https://github.com/serai-dex/serai", package = "monero-clsag" }`
  - Original: [serai-dex/serai](https://github.com/serai-dex/serai) (develop branch) - **the actual code being audited**
  - Audit: Cypher Stack (funded by Monero CCS, audit in progress)
  - Status: Pre-1.0, audit ongoing
  - **Note**: Packages (`monero-clsag`, `monero-serai`, etc.) are reserved on crates.io but not yet in git workspace
  - **Current**: Using mirror temporarily - contains same code being audited, just published by community member
  - **Action**: Monitor serai-dex/serai repository for when packages are added to workspace, then switch to git

- [x] **monero-clsag-mirror 0.1** - Mirrored version of monero-serai CLSAG
  - Used as: Fallback if git dependency unavailable
  - Source: [crates.io](https://crates.io/crates/monero-clsag-mirror)
  - Audit: Same as monero-serai (mirrored)

### Hash Functions (RustCrypto Suite)

- [x] **blake2 0.10.x** - NCC Group audited (RustCrypto suite)
  - Used for: DLEQ challenge computation
  - Source: [RustCrypto](https://github.com/RustCrypto/hashes)

- [x] **sha2 0.10.x** - NCC Group audited (RustCrypto suite)
  - Used for: Hashlock computation
  - Source: [RustCrypto](https://github.com/RustCrypto/hashes)

- [x] **sha3 0.10.x** - NCC Group audited (RustCrypto suite)
  - Used for: CLSAG hash-to-point (Hp)
  - Source: [RustCrypto](https://github.com/RustCrypto/hashes)

### Memory Security

- [x] **zeroize 1.8.x** - RustCrypto suite
  - Used for: Secure secret cleanup
  - Source: [RustCrypto](https://github.com/RustCrypto/zeroize)

## Cairo Side

### Starknet Libraries

- [x] **Garaga v1.0.1** - Audited
  - Used for: Ed25519 MSM operations in Cairo
  - Source: [Garaga](https://github.com/starkware-libs/garaga)

- [x] **OpenZeppelin Cairo v2.0.0** - Audited
  - Used for: ReentrancyGuard, security patterns
  - Source: [OpenZeppelin](https://github.com/OpenZeppelin/cairo-contracts)

- [x] **Cairo stdlib 2.10.0** - Part of Starknet core
  - Used for: Standard Cairo operations
  - Source: [Starknet](https://github.com/starkware-libs/cairo)

## Custom Code Requiring Audit

### High Priority (Cryptographic)

- [ ] **rust/src/clsag/adaptor.rs** (~50 lines)
  - Adaptor CLSAG wrapper around audited library
  - Implements: Partial signature creation, finalization

- [ ] **rust/src/dleq.rs** (~200 lines)
  - DLEQ proof generation
  - Implements: Challenge computation, proof creation

- [ ] **rust/src/serialization.rs** (~100 lines, if exists)
  - Cairo-compatible format conversion
  - Implements: Point/scalar serialization for Cairo

### Medium Priority (Protocol Logic)

- [ ] **rust/src/bin/maker.rs** - Protocol orchestration (maker side)
- [ ] **rust/src/bin/taker.rs** - Protocol orchestration (taker side)
- [ ] **cairo/src/lib.cairo** - AtomicLock contract logic

## Audit Scope Summary

### Current State (After Migration)

- **Custom cryptographic code**: ~350 lines
- **Audited library code**: ~50,000+ lines (monero-serai, curve25519-dalek, RustCrypto)
- **Audit scope reduction**: ~95% reduction from original custom implementation

### Benefits

1. **Leverages $100k+ of community-funded audits** from Monero ecosystem
2. **Reduces custom crypto code** from ~1,500 lines to ~350 lines
3. **Production-grade libraries** used by major projects (Serai DEX)
4. **Ongoing maintenance** by dedicated teams

## Notes

- All cryptographic primitives use audited libraries
- Only protocol-specific code (adaptor extension, DLEQ, serialization) requires custom audit
- Migration to audited libraries eliminates known bugs in custom CLSAG implementation
- Property-based testing (`proptest`) added to catch edge cases

## References

- [Monero CCS Proposals](https://ccs.getmonero.org/)
- [Serai DEX](https://serai.exchange)
- [RustCrypto](https://github.com/RustCrypto)
- [Quarkslab Audit Reports](https://www.quarkslab.com/en/publications)

