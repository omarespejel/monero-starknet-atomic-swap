# Starknet Transaction Signing Implementation

**Date**: December 23, 2025  
**Commit**: `49ad8de`  
**Status**: ✅ Invoke transactions implemented, deployment pending

---

## ✅ IMPLEMENTED: Invoke Transaction Signing

### Transaction Hash Computation

For v1 invoke transactions, the hash is computed as:

```
H(version, sender_address, calldata_hash, max_fee, nonce, chain_id)
```

Where:
- `version` = `0x1` (v1)
- `calldata_hash` = Pedersen hash of all calldata elements
- All values are `FieldElement` (felt252)

**Implementation**: `compute_invoke_tx_hash()` in `rust/src/swap/starknet_manual.rs`

### STARK Curve Signing

Uses `starknet-crypto` crate for ECDSA signing on STARK curve:

```rust
let signature = sign(&private_key_fe, &tx_hash_fe)?;
// Returns Signature { r, s }
```

**Implementation**: `sign_transaction()` in `rust/src/swap/starknet_manual.rs`

### Platform Support

- **Non-macOS**: Full STARK curve signing (production-ready)
- **macOS**: Placeholder signatures (works with devnet `--seed 0`)

**Reason**: `starknet-crypto` depends on `size-of` crate which has macOS compatibility issues (fastcall ABI). macOS uses placeholders for devnet testing.

---

## ⚠️ PENDING: Contract Deployment

Contract deployment requires a different transaction format:

### Deployment Transaction Format

```
starknet_addDeployTransaction {
    "contract_address_salt": felt,
    "constructor_calldata": [felt, ...],
    "contract_definition": { ... },
    "version": "0x1"
}
```

### Deployment Transaction Hash

The hash format for deployment transactions differs from invoke:

```
H(version, contract_address_salt, constructor_calldata_hash, class_hash, ...)
```

**Status**: Not yet implemented. Requires:
1. Deployment transaction hash computation
2. Contract class declaration (if not already declared)
3. Constructor calldata building from DLEQ proof data

---

## 📋 USAGE

### Invoke Transactions (✅ Ready)

```rust
let client = StarknetManualClient::devnet(
    account_address,
    private_key,
    class_hash,
)?;

// Create calls
let calls = vec![Call {
    to: contract_address,
    selector: get_selector_from_name("reveal_secret"),
    data: secret_calldata,
}];

// Submit with real signature (non-macOS) or placeholder (macOS)
let tx_hash = client.submit_invoke_tx(calls).await?;
```

### Contract Deployment (⚠️ Pending)

```rust
// TODO: Implement deploy_and_deposit()
let (contract_address, lock_until) = client.deploy_and_deposit(
    hashlock,
    lock_duration_secs,
    amount,
).await?;
```

---

## 🧪 TESTING

### Unit Tests

```bash
cd rust
cargo test --lib swap::starknet_manual
# ✅ All tests pass
```

### Live Devnet Testing

**Prerequisites**:
1. Start devnet: `docker run -p 5050:5050 shardlabs/starknet-devnet-rs --seed 0`
2. Use devnet account (pre-funded with `--seed 0`)

**Test Invoke**:
```rust
#[tokio::test]
#[ignore] // Requires devnet
async fn test_invoke_with_signing() {
    let client = StarknetManualClient::devnet(...)?;
    let tx_hash = client.reveal_secret(contract, &secret).await?;
    assert!(!tx_hash.is_empty());
}
```

**Test Deployment** (Pending):
```rust
// TODO: Implement when deploy_and_deposit() is ready
```

---

## 📝 NEXT STEPS

1. **Implement Deployment Transaction Hash** (2-3 hours)
   - Research deployment transaction hash format
   - Implement `compute_deploy_tx_hash()`
   - Update `deploy_and_deposit()` to use real signing

2. **Build Constructor Calldata** (1-2 hours)
   - Convert DLEQ proof to Cairo format
   - Build constructor calldata array
   - Include all required hints and points

3. **Live Devnet E2E Test** (1-2 hours)
   - Deploy contract with real DLEQ proof
   - Verify DLEQ proof passes on-chain
   - Test reveal_secret() with real signature

---

## 🔗 REFERENCES

- [Starknet Transaction Format](https://docs.starknet.io/documentation/architecture_and_concepts/Transactions/)
- [starknet-crypto crate](https://crates.io/crates/starknet-crypto)
- [Pedersen Hash Specification](https://docs.starknet.io/documentation/architecture_and_concepts/Hashing/hash-functions/)

