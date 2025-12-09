# Atomic Swap Protocol Specification

## Overview

This document specifies the atomic swap protocol between Monero and Starknet tokens. The protocol uses key splitting, DLEQ proofs, and hashlocks to ensure trustless execution.

## Protocol Parameters

- Hash function: SHA-256 (for hashlocks)
- Challenge hash: BLAKE2s (for DLEQ proofs)
- Elliptic curve: Ed25519 (curve_index=4 in Garaga)
- Timelock minimum: 3 hours (planned for v0.8.0)
- Grace period: 2 hours (planned for v0.8.0)

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

### Step 1: Key Generation

Alice generates:
- `x_partial`: Random scalar (252 bits entropy)
- `t`: Random scalar (252 bits entropy)
- `x = x_partial + t`: Full spend key

### Step 2: Proof Generation

Alice computes:
- `T = t·G`: Adaptor point
- `H = SHA-256(secret_raw_bytes)`: Hashlock (see Serialization Formats section)
- `U = t·Y`: Second point for DLEQ
- `k`: Deterministic nonce (domain-separated SHA-256)
- `R1 = k·G`, `R2 = k·Y`: Commitments
- `c = BLAKE2s("DLEQ" || G || Y || T || U || R1 || R2 || H)`: Challenge
- `s = k + c·t`: Response

### Step 3: Contract Deployment

Alice deploys AtomicLock contract with:
- Hashlock: `H` (8 u32 words)
- Adaptor point: `T` (compressed + sqrt hint)
- DLEQ proof: `(U, c, s, R1, R2)`
- Timelock: `lock_until` (block timestamp + duration)

Constructor verifies DLEQ proof. If invalid, deployment fails.

### Step 4: Token Deposit

Alice calls `deposit()` to transfer tokens into contract. Only depositor can call this function.

### Step 5: Secret Revelation

Bob calls `verify_and_unlock(secret)` with secret `t`. Contract verifies:
1. `SHA-256(secret) == H` (hashlock check)
2. `scalar·G == T` (MSM verification)

If both checks pass, tokens transfer to Bob and contract emits `Unlocked` event.

### Step 6: Key Recovery

Alice monitors for `Unlocked` event, extracts `t`, and recovers:
- `x = x_partial + t`

Alice can now spend Monero with full key `x`.

## Security Properties

### Atomicity

The DLEQ proof ensures that the scalar `t` unlocking Starknet is identical to the scalar needed for Monero. If Bob reveals `t` on Starknet, Alice can recover `x` and spend Monero. If Bob does not reveal `t`, Alice can refund after timelock.

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

## Gas Costs

- DLEQ verification: 270k-440k gas
- Hashlock check: ~10k gas
- MSM verification: ~40k-60k gas per operation
- Token transfer: ~50k-100k gas

Total unlock cost: ~370k-610k gas (depending on MSM complexity).

## Future Enhancements

### Two-Phase Unlock

Planned for v0.8.0. Separate secret revelation from token transfer with grace period to mitigate race conditions.

### Watchtower Service

Planned for production. Monitor both chains and alert parties if cross-chain confirmation fails.

### Batch Operations

Future enhancement. Aggregate multiple swaps into single transaction for gas efficiency.

---

**Version**: 0.7.1-alpha  
**Last Updated**: 2025-12-07

