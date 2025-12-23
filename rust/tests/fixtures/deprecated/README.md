# ⚠️ DEPRECATED TEST VECTORS - SECURITY WARNING

**DO NOT USE IN PRODUCTION**

These test vectors use the UNSAFE single-party key generation pattern
where Alice generates the full Monero spend key.

## Security Issue

Single-party key generation allows Alice to unilaterally spend funds
without Bob's cooperation, breaking atomic swap atomicity.

## Why Keep These?

1. Regression testing of DLEQ proof mechanics (cryptographic primitives)
2. Audit trail proving security fix was implemented
3. Preventing accidental reintroduction of vulnerability

## Secure Alternative

See: `tests/fixtures/protocol/two_party_key_exchange_vectors.json`

## Migration Date

December 23, 2025

## References

- COMIT Network: https://comit.network/blog/2020/10/06/monero-bitcoin/
- Cypher Stack Audit: monero-oxide May 2025

