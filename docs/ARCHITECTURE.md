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

### Phase 1: Setup (Two-Party Key Generation)

**Production Protocol**: Uses two-party key generation (Serai DEX pattern, CypherStack audited):

**Alice generates**:
- `s_a`: Spend key share (kept secret)
- `v_a`: View key share (kept secret)
- `S_a = s_a·G`: Public spend key share
- `V_a = v_a·G`: Public view key share

**Bob generates**:
- `s_b`: Spend key share (kept secret)
- `v_b`: View key share (derived deterministically from `s_b`)
- `S_b = s_b·G`: Public spend key share (adaptor point)
- `V_b = v_b·G`: Public view key share
- `H = SHA-256(s_b_raw_bytes)`: Hashlock (published to Starknet)

**Combined keys**:
- `S = (s_a + s_b)·G`: Combined spend public key
- `V = (v_a + v_b)·G`: Combined view public key
- `x = s_a + s_b`: Full spend key (recovered after `s_b` revealed)

**Bob computes DLEQ proof**:
- DLEQ proof: Proves `∃s_b: SHA-256(s_b) = H ∧ s_b·G = S_b`

**Legacy Protocol** (deprecated): Single-party key splitting:
- `x_partial`: Partial spend key (kept secret)
- `t`: Adaptor scalar (will be revealed)
- `x = x_partial + t`: Full spend key

### Phase 2: Contract Deployment

Bob deploys AtomicLock contract on Starknet with:
- Hashlock `H` (8 u32 words, SHA-256 of `s_b` raw bytes)
- Adaptor point `S_b` (compressed Edwards, 32 bytes)
- DLEQ proof (challenge, response, commitments) proving hashlock binds to adaptor point
- Timelock (minimum 3 hours)
- Explicit depositor address for deposit/refund authorization

**Security**: Contract constructor verifies DLEQ proof. If invalid, deployment fails. This cryptographically binds the hashlock to the adaptor point, preventing hashlock substitution attacks.

### Phase 3: Token Deposit

Alice calls `deposit()` to transfer tokens into the contract. Only Alice
(the explicit constructor depositor) can deposit. This is intentionally not
derived from constructor caller because UDC deployment changes the caller to UDC.

### Phase 4: Secret Revelation

Bob reveals secret `s_b` by calling `reveal_secret(s_b)` or the legacy
reveal-only `verify_and_unlock(s_b)` alias. Contract verifies:
- `SHA-256(s_b_raw_bytes) == H` (hashlock check)
- `s_b·G == S_b` (MSM verification via Garaga)

If verification succeeds, the secret and unlocker are recorded and
`SecretRevealed` is emitted. Tokens are not transferred yet. After the grace
period, the unlocker calls `claim_tokens()` to transfer tokens and emit
`TokensClaimed`/`Unlocked`.

**Security**: Two-phase unlock with grace period (2 hours) mitigates race conditions between secret revelation and cross-chain confirmation.

### Phase 5: Key Recovery

Alice monitors Starknet for `Unlocked` event, extracts revealed `s_b`, and recovers full key:
- `x = s_a + s_b` (using `recover_spend_key(s_a, s_b)`)

Alice can now spend Monero using the full key `x` with standard Monero wallet software.

**Security Property**: Neither Alice nor Bob can spend alone. Both shares are required to recover the full spend key.

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

### Two-Party Key Generation (Production)

Uses the Serai DEX pattern (CypherStack audited): `x = s_a + s_b` where:
- Alice generates `s_a` (spend share) and `v_a` (view share)
- Bob generates `s_b` (spend share) and `v_b` (view share, derived deterministically)
- Combined keys: `S = (s_a + s_b)·G`, `V = (v_a + v_b)·G`
- Full spend key: `x = s_a + s_b` (recovered after `s_b` revealed)

Only the public curve points `S_a`, `V_a`, `S_b`, and `V_b` belong in public
key-exchange data. View-share scalars and the combined view scalar are
wallet-scanning material and must stay in local secret artifacts or an explicit
operator handoff.

**Security Properties**:
- Neither party can spend alone (requires both shares)
- Zero-scalar rejection (P0 audit fix)
- BN254 compatibility checks (prevents Light Protocol #237 vulnerability)
- Malicious Alice attack prevention (fake `S_a` cannot steal funds)

**Legacy**: Single-party key splitting (`x = x_partial + t`) is deprecated but still supported for backward compatibility.

### DLEQ Proofs

Discrete logarithm equality proofs bind the hashlock to the adaptor point. The proof demonstrates that a single scalar `t` satisfies both `SHA-256(t) = H` and `t·G = T` without revealing `t`.

### Hashlocks

SHA-256 commitments provide 256 bits of security. The hashlock is verified on-chain before expensive elliptic curve operations, providing fail-fast behavior.

## Component Responsibilities

### Rust Library

- **Two-party key generation**: `monero/two_party_keys.rs` - AliceKeys, BobKeys, SharedOutput
- **Key splitting** (legacy): `monero/key_splitting.rs` - Single-party approach
- **DLEQ proof generation**: `dleq.rs` - Create proofs binding hashlock to adaptor point
- **Scalar compatibility**: `crypto/scalar_compat.rs` - Ed25519→BN254 safety checks
- **Race condition monitoring**: `swap/race_monitor.rs` - Detect protocol-level race conditions
- **Serialization**: Convert between Rust and Cairo formats
- **Test utilities**: Generate test vectors and verify compatibility

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

### Race Condition Monitoring

A protocol-level race condition exists between secret revelation and cross-chain confirmation. The `RaceConditionMonitor` detects if:
- Secret is revealed on Starknet before Monero transaction has sufficient confirmations
- Timelock expires before cross-chain confirmation completes

**Mitigations**:
- Two-phase unlock with grace period (2 hours)
- Race condition monitoring module (`swap/race_monitor.rs`)
- Minimum timelock enforcement (3 hours)

**Status**: Monitoring implemented, automatic mitigation planned for future versions.

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

**Version**: 0.7.1 (Two-Party Key Generation)  
**Last Updated**: 2025-12-23
