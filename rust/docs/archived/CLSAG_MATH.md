# CLSAG Mathematics for Adaptor Signatures

## Standard CLSAG Signing (at real index π)

### 1. Setup

- Secret key: x (only signer knows)
- Public key: P = x·G
- Key image: I = x·Hp(P)

### 2. Generate nonce

- α ← random scalar
- L = α·G
- R = α·Hp(P)

### 3. Compute challenges around the ring

- c_{π+1} = H(msg || L || R)
- For i = π+1, ..., n-1, 0, ..., π-1:
  - s_i ← random
  - L_i = s_i·G + c_i·P_i
  - R_i = s_i·Hp(P_i) + c_i·I
  - c_{i+1} = H(msg || L_i || R_i)

### 4. Close the ring

- s_π = α - c_π·x

## Adaptor Modification

**Key insight**: Split the secret key into two parts:

- x = x_base + t

- Where t is the adaptor scalar (goes to Starknet)

**Partial signature** (without knowing final t):

- s'_π = α - c_π·x_base

**Finalization** (when t is revealed):

- s_π = s'_π - c_π·t = α - c_π·(x_base + t) = α - c_π·x ✓

## Adaptor Extraction

If Alice publishes partial sig, Bob unlocks on Starknet revealing t,

Alice can compute: t = (s_π - s'_π) / (-c_π)

But in our flow, Alice CREATES the partial sig and already knows t.

She just waits for Bob to reveal t by unlocking, then finalizes.

