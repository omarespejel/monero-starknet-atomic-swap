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

A protocol-level race condition exists between secret revelation and cross-chain confirmation. If a Monero transaction fails or experiences a reorganization after the secret is revealed, funds may be at risk. Mitigations are planned for version 0.8.0.

### Monero Integration

The current Monero integration is demo-level. A production implementation would require full CLSAG signing, key image handling, change outputs, and multi-output transactions.

### Testnet Only

The protocol is designed for testnet use only. Mainnet deployment requires external review and race condition mitigations.

---

**Version**: 0.8.0-alpha  
**Last Updated**: 2025-12-07

