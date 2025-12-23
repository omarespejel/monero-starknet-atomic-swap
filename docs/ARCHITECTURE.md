# Architecture Overview

## System Components

```
┌─────────────────────────────────────────────────────────────┐
│                      ATOMIC SWAP PROTOCOL                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────┐    DLEQ Proof    ┌─────────────┐          │
│  │   MONERO    │ ←───────────────→ │  STARKNET   │          │
│  │   DOMAIN    │                   │   DOMAIN    │          │
│  └─────────────┘                   └─────────────┘          │
│        │                                 │                   │
│        ▼                                 ▼                   │
│  ┌─────────────┐                   ┌─────────────┐          │
│  │ Key Split   │                   │ AtomicLock  │          │
│  │ x=x_p + t   │                   │  Contract   │          │
│  └─────────────┘                   └─────────────┘          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## Protocol Flow

### Phase 1: Setup

Alice generates a swap key pair using key splitting:
- `x_partial`: Partial spend key (kept secret)
- `t`: Adaptor scalar (will be revealed)
- `x = x_partial + t`: Full spend key

Alice computes:
- `T = t·G`: Adaptor point (published to Starknet)
- `H = SHA-256(t)`: Hashlock (published to Starknet)
- DLEQ proof: Proves `∃t: SHA-256(t) = H ∧ t·G = T`

### Phase 2: Contract Deployment

Alice deploys AtomicLock contract on Starknet with:
- Hashlock `H` (8 u32 words)
- Adaptor point `T` (compressed Edwards, 32 bytes)
- DLEQ proof (challenge, response, commitments)
- Timelock (minimum 3 hours)

Contract constructor verifies DLEQ proof. If invalid, deployment fails.

### Phase 3: Token Deposit

Alice calls `deposit()` to transfer tokens into the contract. Only Alice (depositor) can deposit.

### Phase 4: Secret Revelation

Bob reveals secret `t` by calling `verify_and_unlock(t)`. Contract verifies:
- `SHA-256(t) == H` (hashlock check)
- `t·G == T` (MSM verification via Garaga)

If verification succeeds, tokens transfer to Bob and contract emits `Unlocked` event.

### Phase 5: Key Recovery

Alice monitors Starknet for `Unlocked` event, extracts revealed `t`, and recovers full key:
- `x = x_partial + t`

Alice can now spend Monero using the full key `x` with standard Monero wallet software.

## Trust Boundaries

```
┌──────────────────┐     ┌──────────────────┐
│  Trusted (Rust)  │     │ Verified (Cairo) │
│                  │     │                  │
│ - Key generation │────▶│ - DLEQ verify    │
│ - DLEQ proofs    │     │ - MSM checks     │
│ - Signatures     │     │ - State machine  │
└──────────────────┘     └──────────────────┘
```

The Rust side generates secrets and proofs. The Cairo side verifies proofs and manages state. No trust is required between parties - the cryptographic proofs ensure atomicity.

## Cryptographic Primitives

### Key Splitting

Uses the Serai DEX pattern: `x = x_partial + t`. This avoids modifying Monero's CLSAG signature scheme while still enabling atomic swaps. The approach has been validated by CypherStack's review of Serai.

### DLEQ Proofs

Discrete logarithm equality proofs bind the hashlock to the adaptor point. The proof demonstrates that a single scalar `t` satisfies both `SHA-256(t) = H` and `t·G = T` without revealing `t`.

### Hashlocks

SHA-256 commitments provide 256 bits of security. The hashlock is verified on-chain before expensive elliptic curve operations, providing fail-fast behavior.

## Component Responsibilities

### Rust Library

- Key splitting: Generate and recover swap keys
- DLEQ proof generation: Create proofs binding hashlock to adaptor point
- Serialization: Convert between Rust and Cairo formats
- Test utilities: Generate test vectors and verify compatibility

### Cairo Contract

- DLEQ verification: Verify proofs using Garaga MSM
- State management: Track locked/unlocked state
- Access control: Enforce depositor-only operations
- Reentrancy protection: Prevent recursive calls

### Python Tools

- Hint generation: Generate MSM hints for Garaga
- Verification: Verify Rust-Cairo compatibility
- Conversion: Convert between hex and Cairo u256 formats

## Security Properties

### Atomicity

Either both parties complete the swap or neither does. The DLEQ proof ensures the secret unlocking Starknet is the same secret needed for Monero. The timelock provides a refund path if the swap fails.

### Trustlessness

No trusted third party required. The cryptographic proofs ensure that parties cannot cheat. The contract enforces the protocol rules.

### Verifiability

All cryptographic operations are verifiable on-chain. The DLEQ proof can be independently verified by anyone. The hashlock and adaptor point are public.

## Known Limitations

### Race Condition

A protocol-level race condition exists between secret revelation and cross-chain confirmation. If a Monero transaction fails or experiences a reorganization after the secret is revealed, funds may be at risk. Mitigations are planned for future versions.

### Monero Integration

**Production-ready** - Uses `monero-wallet-rpc` (auditor-approved approach):

- ✅ **CLSAG signing** - Handled by wallet-rpc (Monero's own code)
- ✅ **Key image handling** - Handled by wallet-rpc
- ✅ **Change outputs** - Handled by wallet-rpc
- ✅ **Multi-output transactions** - Supported via wallet-rpc

This is intentionally conservative - we use Monero's audited code rather than implementing custom crypto. The same approach has been used successfully by COMIT/UnstoppableSwap for 3+ years on mainnet.

### Testnet Only

The protocol is designed for testnet use only. Mainnet deployment requires external review and race condition mitigations.

## Technical Implementation Details

### Sqrt Hint Prevention

**Golden Rule**: Never generate sqrt hints from Python/Rust mathematical computation. Always validate sqrt hints through Cairo/Garaga decompression tests.

**Protection Layers**:
- Pre-commit hook validates sqrt hints
- GitHub Actions validates on every PR
- Authoritative hints documented in `cairo/tests/fixtures/AUTHORITATIVE_SQRT_HINTS.cairo`
- Validation scripts: `tools/validate_sqrt_hints.py`

**How to Update Sqrt Hints**:
1. Generate candidates (optional): `python tools/discover_sqrt_hints.py <compressed_point_hex>`
2. Test in Cairo: Update `test_unit_point_decompression.cairo` and run `snforge test`
3. If test passes: Copy working hint to `AUTHORITATIVE_SQRT_HINTS.cairo`
4. Validate: `python tools/validate_sqrt_hints.py rust/test_vectors.json`

**Root Cause**: Sqrt hints generated with Python's `fix_hints.py` use a different algorithm than Garaga expects. Solution: Use empirically-validated hints from passing Cairo tests.

### Development Best Practices

**Branch Strategy**: Create dedicated branches for critical fixes (e.g., `fix/p0-critical-fixes`)

**Incremental Fixes**: Fix issues separately, one commit per fix. Test after each change.

**Test-First Approach**: Write failing tests that demonstrate bugs before fixing.

**Validation Gates**: Run validation scripts after each fix to ensure no regressions.

**Rollback Plan**: Create checkpoint tags before dangerous changes. Know how to revert individual commits.

---

**Version**: 0.1.0  
**Last Updated**: 2025-12-20

