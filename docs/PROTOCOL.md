# Atomic Swap Protocol Specification

## Overview

This document specifies the atomic swap protocol between Monero and Starknet tokens. The protocol uses **two-party key generation** (Serai DEX pattern, CypherStack audited), DLEQ proofs, and hashlocks to ensure trustless execution.

**Production Protocol**: Two-party key generation (`x = s_a + s_b`)  
**Legacy Protocol**: Single-party key splitting (`x = x_partial + t`) - deprecated but supported

## Product Directions

The backend now treats swap direction as an explicit quote term, not something
to infer from token names or UI copy.

### XMR -> Starknet

User sends XMR and receives a Starknet token claim. This is the first path for
Monero users entering Starknet.

1. Liquidity provider creates/funds the Starknet `AtomicLock`.
2. User sends the exact XMR amount to the generated Monero swap address.
3. After Monero finality, the Starknet-token claimer reveals the secret on
   Starknet.
4. The Monero claimant watches `SecretRevealed`, reconstructs the spend key,
   and sweeps XMR.
5. After the grace period, the Starknet-token claimer claims the locked token.

For the privacy-pool version, step 5 should later be replaced by a helper that
claims into a privacy-pool open note instead of a public wallet balance.

### Starknet -> XMR

User locks a Starknet token and receives XMR. This is the exit path for users
leaving Starknet into Monero.

1. User creates/funds the Starknet `AtomicLock`.
2. Liquidity provider sends the exact XMR amount to the generated Monero swap
   address.
3. After Monero finality, the Starknet-token claimer reveals the secret on
   Starknet.
4. User-side Monero claimant watches `SecretRevealed`, reconstructs the spend
   key, and sweeps XMR to the user's Monero address.
5. After the grace period, the Starknet-token claimer claims the locked token.

Both directions use the same Starknet contract. The difference is product role
assignment, quote terms, and which side controls the Monero claim automation.

## Protocol Parameters

- Hash function: SHA-256 (for hashlocks)
- Challenge hash: Poseidon (for DLEQ proofs; BLAKE2s kept for future enablement)
- Elliptic curve: Ed25519 (curve_index=4 in Garaga)
- Timelock minimum: 3 hours (✅ implemented in P0 fixes)
- Grace period: 2 hours (✅ implemented in two-phase unlock)

## Serialization Formats (CRITICAL)

### Hashlock Computation

**H = SHA-256(secret_raw_bytes)**

Where `secret_raw_bytes` is the 32-byte secret **BEFORE** any scalar reduction.

⚠️ **DO NOT** use `Scalar::from_bytes_mod_order(secret).to_bytes()` - 
this may produce different bytes after mod reduction, causing hashlock mismatch.

**Why Raw Bytes?**

Cairo's `verify_and_unlock` receives the secret as a `ByteArray` and computes
`SHA-256(secret_bytes)` directly. There is no scalar reduction in Cairo's hashlock computation.

**Example:**

```rust
// ✅ CORRECT (for deployment)
let secret_bytes = [0x12u8; 32];
let hashlock = SHA256::digest(secret_bytes);

// ❌ WRONG (causes mismatch with Cairo)
let secret = Scalar::from_bytes_mod_order(secret_bytes);
let hashlock = SHA256::digest(secret.to_bytes());  // May differ!
```

**Storage Format:**

Hashlock is stored in contract as 8 u32 words (big-endian from hash, little-endian interpretation).

## Message Formats

### DLEQ Proof

A DLEQ proof consists of:
- `second_point`: Edwards point `U = t·Y` (compressed, 32 bytes)
- `challenge`: Scalar `c` (32 bytes)
- `response`: Scalar `s = k + c·t` (32 bytes)
- `r1`: Commitment `R1 = k·G` (compressed, 32 bytes)
- `r2`: Commitment `R2 = k·Y` (compressed, 32 bytes)

### Hashlock

The hashlock is computed as:
```
H = SHA-256(secret_raw_bytes)
```

Where `secret_raw_bytes` is the 32-byte secret **BEFORE** any scalar reduction.

⚠️ **CRITICAL**: DO NOT use `Scalar::from_bytes_mod_order(secret).to_bytes()` - 
this may produce different bytes after mod reduction, causing hashlock mismatch.

**Why Raw Bytes?**

Cairo's `verify_and_unlock` receives the secret as a `ByteArray` and computes
`SHA-256(secret_bytes)` directly. There is no scalar reduction in Cairo's hashlock computation.

**Serialization Format:**

Stored in contract as 8 u32 words (big-endian from hash, little-endian interpretation).

### Adaptor Point

The adaptor point is computed as:
```
T = t·G
```

Stored in contract as compressed Edwards point (32 bytes) with sqrt hint for decompression.

## Protocol Steps

### Step 1: Two-Party Key Generation (Production)

**Alice generates**:
- `s_a`: Spend key share (random scalar, 252 bits entropy)
- `v_a`: View key share (random scalar, 252 bits entropy)
- `S_a = s_a·G`: Public spend key share
- `V_a = v_a·G`: Public view key share

**Bob generates**:
- `s_b`: Spend key share (random scalar, 252 bits entropy)
- `v_b`: View key share (derived deterministically: `SHA-256("VIEW_KEY_V1" || s_b_bytes)`)
- `S_b = s_b·G`: Public spend key share (adaptor point)
- `V_b = v_b·G`: Public view key share
- `H = SHA-256(s_b_raw_bytes)`: Hashlock

**Combined keys**:
- `S = (s_a + s_b)·G`: Combined spend public key
- `V = (v_a + v_b)·G`: Combined view public key
- `x = s_a + s_b`: Full spend key (recovered after `s_b` revealed)

**Security Properties**:
- Neither party can spend alone (requires both shares)
- Zero-scalar rejection (P0 audit fix)
- BN254 compatibility checks (prevents Light Protocol #237 vulnerability)

### Step 2: DLEQ Proof Generation

Bob computes DLEQ proof for `s_b`:
- `S_b = s_b·G`: Adaptor point (same as public spend key share)
- `U = s_b·Y`: Second point (where `Y` is second generator)
- `H = SHA-256(s_b_raw_bytes)`: Hashlock
- DLEQ proof: Proves `∃s_b: SHA-256(s_b) = H ∧ s_b·G = S_b`

**Legacy Protocol** (deprecated):
- Alice generates: `x_partial`, `t`, `x = x_partial + t`
- Alice computes: `T = t·G` (adaptor point)
- `H = SHA-256(secret_raw_bytes)`: Hashlock (see Serialization Formats section)
- `U = t·Y`: Second point for DLEQ
- `k`: Deterministic nonce (domain-separated SHA-256)
- `R1 = k·G`, `R2 = k·Y`: Commitments
- `c = Poseidon("DLEQ" || G || Y || T || U || R1 || R2 || H)`: Challenge
- `s = k + c·t`: Response

### Step 3: Contract Deployment

Alice deploys AtomicLock contract with:
- Hashlock: `H` (8 u32 words)
- Adaptor point: `T` (compressed + sqrt hint)
- DLEQ proof: `(U, c, s, R1, R2)`
- Timelock: `lock_until` (block timestamp + duration)
- Depositor: Alice's account address, passed explicitly in constructor calldata

Constructor verifies DLEQ proof. If invalid, deployment fails.

### Step 4: Token Deposit

Alice calls `deposit()` to transfer tokens into contract. Only the explicit
constructor depositor can call this function. This must not be inferred from the
constructor caller because UDC deployment makes the caller the UDC contract.

### Step 5: Secret Revelation (Two-Phase Unlock)

**Phase 1: Reveal Secret** (`reveal_secret()`)

Bob calls `reveal_secret(secret)` with secret `t`. Contract verifies:
1. `SHA-256(secret) == H` (hashlock check)
2. `scalar·G == T` (MSM verification)

If both checks pass:
- Contract stores `secret_revealed = true`
- Contract stores `reveal_timestamp = block_timestamp`
- Contract stores `unlocker_address = caller`
- Contract emits `SecretRevealed` event
- **Tokens are NOT transferred yet** (grace period active)

**Phase 2: Claim Tokens** (`claim_tokens()`)

After grace period expires (2 hours), Bob calls `claim_tokens()`:
- Requires `secret_revealed == true`
- Requires `block_timestamp >= reveal_timestamp + GRACE_PERIOD`
- Requires `caller == unlocker_address`

If all checks pass:
- Tokens transfer to Bob
- Contract sets `unlocked = true`
- Contract emits `TokensClaimed` event

**Backward Compatibility** (`verify_and_unlock()`)

The original `verify_and_unlock(secret)` function still works:
- Calls `reveal_secret()` internally
- Does not transfer tokens
- Requires the same later `claim_tokens()` call after the grace period
- Maintains backward compatibility for reveal integrations without keeping the
  legacy immediate-unlock behavior

### Step 6: Key Recovery

Alice monitors for `SecretRevealed` event (or `Unlocked` for backward compatibility), extracts `t`, and recovers:
- `x = x_partial + t`

Alice can now spend Monero with full key `x`.

**Grace Period Purpose:**

The 2-hour grace period allows time for:
- **Monero transaction finality (10 confirmations ≈ 20 minutes)** - CRITICAL REQUIREMENT
- Cross-chain verification
- Watchtower monitoring and alerts

This mitigates race conditions where tokens could be claimed before Monero confirms.

**Monero Finality Requirement:**

Before calling `claim_tokens()`, the Monero transaction MUST have reached **10 confirmations** (approximately 20 minutes at Monero's 2-minute block time). This is enforced by the `wait_for_finality()` helper function in the Rust implementation.

**Why 10 Confirmations?**

- Matches [Monerica recommendation](https://blog.monerica.com/articles/how-many-confirmations-for-monero) for high-value transactions
- Provides strong reorg resistance (10-block reorg is extremely rare on Monero mainnet)
- Industry standard used by COMIT Network and UnstoppableSwap for atomic swaps
- Balances security (reorg resistance) with user experience (reasonable wait time)

**Implementation:**

The `wait_for_finality()` function polls the Monero wallet RPC until the transaction reaches the required confirmations:

```rust
use xmr_secret_gen::monero::wait_for_default_finality;

// Wait for 10 confirmations (default)
let transfer_info = wait_for_default_finality(&wallet_client, txid).await?;

// Now safe to call claim_tokens()
```

**Security Note:** The grace period (2 hours) is longer than the typical confirmation time (20 minutes) to provide additional safety margin and allow for network delays or temporary RPC unavailability.

## Security Properties

### Atomicity

The DLEQ proof ensures that the scalar `s_b` unlocking Starknet is identical to the scalar needed for Monero. If Bob reveals `s_b` on Starknet, Alice can recover `x = s_a + s_b` and spend Monero. If Bob does not reveal `s_b`, Alice can refund after timelock.

**Two-Party Security**: Neither Alice nor Bob can spend alone. Both shares (`s_a` and `s_b`) are required to recover the full spend key `x`.

### Trustlessness

No trusted third party required. The cryptographic proofs ensure protocol correctness. The contract enforces all rules.

### Verifiability

All operations are verifiable. The DLEQ proof can be independently verified. The hashlock and adaptor point are public.

## Error Conditions

### Invalid DLEQ Proof

If the DLEQ proof is invalid, contract deployment fails. This prevents binding incorrect hashlocks to adaptor points.

### Wrong Secret

If Bob provides wrong secret, `verify_and_unlock()` reverts. The hashlock check fails before expensive operations.

### Timelock Not Expired

If Alice tries to refund before timelock expires, `refund()` reverts. This prevents premature refunds.

### Already Unlocked

If contract is already unlocked, further unlock or refund attempts revert. This prevents double-spending.

### Secret Already Revealed

If secret has been revealed (Phase 1 complete), `refund()` is blocked. This prevents depositor from stealing tokens during grace period.

## Gas Costs

- DLEQ verification: 270k-440k gas
- Hashlock check: ~10k gas
- MSM verification: ~40k-60k gas per operation
- Token transfer: ~50k-100k gas

Total unlock cost: ~370k-610k gas (depending on MSM complexity).

## Implemented Enhancements

### Two-Phase Unlock ✅

**Status:** Implemented

Separates secret revelation from token transfer with 2-hour grace period to mitigate race conditions. See Step 5 above for details.

**Security Benefits:**
- Prevents depositor refund after secret revealed (P0 fix)
- Allows time for Monero confirmation before token claim
- Enables watchtower monitoring and alerts

### Watchtower Service

Planned for production. Monitor both chains and alert parties if cross-chain confirmation fails. See `watchtower/` directory for skeleton implementation.

### Batch Operations

Future enhancement. Aggregate multiple swaps into single transaction for gas efficiency.

---

**Version**: 0.7.1 (Two-Party Key Generation)  
**Last Updated**: 2025-12-23
