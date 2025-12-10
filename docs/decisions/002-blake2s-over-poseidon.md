# ADR-002: BLAKE2s Over Poseidon for DLEQ Challenge

## Status

Accepted (2025-12-05)

## Context

The DLEQ proof challenge computation requires a hash function. Two options were considered:

1. **Poseidon**: Starknet-native hash function, designed for zero-knowledge proofs
2. **BLAKE2s**: Standard cryptographic hash, supported by Cairo stdlib

## Decision

Use BLAKE2s for challenge computation.

## Rationale

### Gas Efficiency

- BLAKE2s: 50k-80k gas for challenge computation
- Poseidon: 400k-640k gas for challenge computation
- **8x gas savings** with BLAKE2s

### Standard Library Support

- BLAKE2s available in Cairo stdlib (`core::blake`)
- No external dependencies required
- Well-tested and widely used

### Compatibility

- Rust `blake2` crate provides identical implementation
- Easy to verify Rust-Cairo compatibility
- Standard cryptographic hash (RFC 7693)

### Security

- BLAKE2s provides 256 bits of security
- Cryptographically secure for challenge computation
- No security concerns compared to Poseidon

## Consequences

### Positive

- Significant gas savings (8x reduction)
- Simpler implementation (standard library)
- Better compatibility between Rust and Cairo
- Easier to review (standard hash function)

### Negative

- Not using Starknet-native hash function
- Slightly less "Starknet-native" feel

### Neutral

- Security properties equivalent
- No functional differences

## Alternatives Considered

### Poseidon

**Rejected** because:
- 8x more expensive in gas
- Requires external library or custom implementation
- No significant security advantage for this use case
- More complex to verify Rust-Cairo compatibility

### SHA-256

**Considered but not chosen** because:
- BLAKE2s is faster and more modern
- Both provide equivalent security
- BLAKE2s has better Cairo stdlib support

## Implementation Notes

Challenge computation uses BLAKE2s with domain separation:
```
c = BLAKE2s("DLEQ" || G || Y || T || U || R1 || R2 || hashlock) mod n
```

The "DLEQ" prefix provides domain separation to prevent hash collisions with other protocol components.

## Gas Benchmarks

| Hash Function | Challenge Gas | Total DLEQ Gas |
|---------------|---------------|---------------|
| BLAKE2s | 50k-80k | 270k-440k |
| Poseidon | 400k-640k | 620k-1000k |

**Conclusion**: BLAKE2s provides 8x gas savings with equivalent security.

## References

- BLAKE2 Specification (RFC 7693): https://www.rfc-editor.org/rfc/rfc7693
- Cairo stdlib documentation: https://docs.starknet.io/documentation/architecture_and_concepts/Smart_Contracts/cairo-common-library/
- Gas optimization analysis: See README.md Gas Benchmarks section

---

**Author**: Development Team  
**Date**: 2025-12-05  
**Status**: Accepted

