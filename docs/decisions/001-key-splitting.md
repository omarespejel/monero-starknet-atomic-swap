# ADR-001: Key Splitting Over CLSAG Adaptor

## Status

Accepted (2025-12-06)

## Context

We need to cryptographically bind a Starknet hashlock to a Monero spending key to enable atomic swaps. Three approaches were considered:

1. **Custom CLSAG adaptor signatures**: Modify Monero's CLSAG signature scheme to include an adaptor point
2. **Key splitting**: Split the Monero key into two parts, reveal one part on Starknet
3. **Two-party ECDSA**: Use threshold signatures (complex, not Monero-native)

## Decision

Use key splitting: `x = x_partial + t`

## Rationale

### Security

- Uses only audited curve25519-dalek operations
- No custom cryptographic implementations
- Matches pattern validated by CypherStack review of Serai DEX

### Simplicity

- Approximately 50 lines of code vs 500+ lines for custom CLSAG
- Easier to review and verify
- Clear separation of concerns

### Precedent

- Serai DEX uses identical pattern (CypherStack validated)
- Tari Protocol RFC-0241 documents same approach
- Pattern validated in Monero community review

### No Custom Crypto

- Avoids implementing ring signatures
- Uses standard Ed25519 operations only
- All cryptographic primitives from audited libraries

## Consequences

### Positive

- Simpler codebase, easier to review
- No CLSAG modification needed
- Can use standard Monero wallet software after key recovery
- Matches industry best practices

### Negative

- Requires handling adaptor scalar separately
- Slightly more complex key management
- Must ensure proper zeroization of secrets

### Neutral

- Performance impact negligible
- Gas costs unchanged (on-chain operations same)

## Alternatives Considered

### Custom CLSAG Adaptor

**Rejected** because:
- Requires implementing ring signatures (complex)
- High risk of bugs (InvalidC1 error found in custom implementation)
- No production reference implementation
- Violates "no custom crypto" principle

### Two-Party ECDSA

**Rejected** because:
- Not Monero-native (Monero uses CLSAG, not ECDSA)
- Requires threshold signature scheme
- Much more complex than needed

## Implementation Notes

The key splitting is implemented in `rust/src/monero/key_splitting.rs`:
- `SwapKeyPair::generate()`: Creates split key pair
- `SwapKeyPair::recover()`: Recovers full key when `t` is revealed
- All secrets wrapped in `Zeroizing<Scalar>` for memory safety

## References

- Serai DEX: https://github.com/serai-dex/serai
- Tari RFC-0241: Key splitting pattern
- Monero Community Review: https://ccs.getmonero.org/proposals/monero-serai-wallet-audit.html
- CypherStack Review Report: Serai DEX security review

---

**Author**: Development Team  
**Date**: 2025-12-06  
**Status**: Accepted

