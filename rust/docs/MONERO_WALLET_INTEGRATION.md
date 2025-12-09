# Monero Wallet RPC Integration Guide

## Overview

This guide documents the production-grade Monero wallet RPC integration for atomic swaps between Starknet and Monero, following COMIT Network's battle-tested patterns from 3+ years of mainnet operation.

## Architecture

```
┌─────────────────┐         ┌──────────────────┐         ┌─────────────────┐
│  Starknet       │         │  Your Rust Code  │         │  Monero Wallet  │
│  Cairo Contract │◄────────│  Integration     │◄────────│  RPC Service    │
│                 │         │  Layer           │         │                 │
└─────────────────┘         └──────────────────┘         └─────────────────┘
                                     │
                                     │
                            ┌────────▼────────┐
                            │  Monero Daemon  │
                            │  (stagenet)     │
                            └─────────────────┘
```

## Prerequisites

### 1. Monero Software

Download Monero CLI from [getmonero.org](https://www.getmonero.org/downloads/):

```bash
# Linux/Mac
wget https://downloads.getmonero.org/cli/monero-linux-x64-v0.18.3.1.tar.bz2
tar -xvf monero-linux-x64-v0.18.3.1.tar.bz2
cd monero-x86_64-linux-gnu-v0.18.3.1/
```

### 2. Stagenet Daemon (Optional - can use public node)

```bash
# Option A: Use public node (recommended for development)
# No setup needed - code uses stagenet.xmr-tw.org:38081

# Option B: Run local daemon (recommended for production)
./monerod --stagenet --detach
```

### 3. Wallet RPC (REQUIRED)

```bash
# Start wallet-rpc
./monero-wallet-rpc \
  --stagenet \
  --daemon-address stagenet.xmr-tw.org:38081 \
  --rpc-bind-port 38088 \
  --rpc-bind-ip 127.0.0.1 \
  --disable-rpc-login \
  --wallet-dir ./wallets \
  --log-level 2

# Keep this running in a separate terminal
```

## Quick Start

### 1. Add Dependencies

Already configured in `rust/Cargo.toml`:

```toml
monero = "0.12"
jsonrpc_client = { version = "0.7", features = ["reqwest"] }
monero-epee-bin-serde = "1"
rust_decimal = { version = "1", features = ["serde-float"] }
```

### 2. Run Integration Tests

```bash
# Terminal 1: Start wallet-rpc (see Prerequisites #3)
./monero-wallet-rpc --stagenet --rpc-bind-port 38088 [...]

# Terminal 2: Run tests
cd rust
cargo test --test wallet_integration_test -- --ignored

# Expected output:
# ✅ Created new wallet
# 📍 Stagenet address: 5A1...
# 💰 Balance: 0 XMR
```

### 3. Fund Wallet for Testing

```bash
# Get your stagenet address from test output
# Visit: https://stagenet-faucet.xmr-tw.org/
# Enter address, solve captcha, receive 1 XMR

# Wait 10 minutes for confirmation
# Re-run tests to verify balance
cargo test test_wallet_connection_and_balance -- --ignored
```

## Core Functions

### Create Locked Transaction

```rust
// This is THE critical function for atomic swaps
// Amount in piconero: 1 XMR = 10^12 piconero
let amount_piconero = 100_000_000_000; // 0.1 XMR
let result = wallet.transfer_locked(
    &destination_address,
    amount_piconero,
    unlock_height, // Block height when funds unlock
).await?;

println!("TX: {}", result.tx_hash);
```

### Wait for Confirmations (10-block COMIT standard)

```rust
// COMIT's production standard: 10 confirmations
wallet.wait_for_confirmations(&tx_hash, 10).await?;
// Takes ~20 minutes (2 min per block)
```

### Verify Key Image

```rust
// Prevents double-spending
let tx_info = wallet.get_transfer_by_txid(&tx_hash).await?;
assert!(tx_info.confirmations >= 10);
```

## Testing Strategy

### Level 1: Connection Test (5 seconds)

```bash
cargo test test_wallet_connection_and_balance -- --ignored
```

### Level 2: Transaction Test (~5 minutes)

```bash
cargo test test_locked_transaction_creation -- --ignored
```

### Level 3: Production Safety Test (~20 minutes)

```bash
cargo test test_ten_confirmation_safety -- --ignored
```

### Level 4: Refund Scenario (~10 minutes)

```bash
cargo test test_refund_scenario -- --ignored
```

## Production Checklist

- [ ] Wallet RPC running and synced
- [ ] Connection test passing
- [ ] Locked transaction test passing
- [ ] 10-confirmation test passing
- [ ] Refund scenario validated
- [ ] Key image verification working
- [ ] Error handling tested
- [ ] Timelock coordination verified with Starknet

## Troubleshooting

### "Failed to connect to wallet-rpc"

```bash
# Check if wallet-rpc is running
curl -X POST http://localhost:38088/json_rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_version"}'

# Should return: {"id":"0","jsonrpc":"2.0","result":{"version":...}}
```

### "Wallet has no balance"

```bash
# Fund via stagenet faucet
# Visit: https://stagenet-faucet.xmr-tw.org/
# Wait 10 minutes for confirmation
```

### "Daemon not synced"

```bash
# Check daemon sync status
curl -X POST http://stagenet.xmr-tw.org:38081/json_rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_info"}'

# Look for "synchronized": true
```

## Docker Setup (Alternative)

```bash
# Use provided docker-compose.yml
docker-compose up -d

# Wait for sync (~30-60 min first time)
docker logs -f monerod-stagenet

# Once synced, run tests
cargo test --test wallet_integration_test -- --ignored
```

## Security Considerations

### 1. Private Key Management

```rust
// NEVER hardcode passwords
let password = std::env::var("WALLET_PASSWORD")
    .expect("WALLET_PASSWORD must be set");

wallet.open_wallet(&password).await?;
```

### 2. Timelock Coordination

```rust
// CRITICAL: Monero must unlock BEFORE Starknet expires
const STARKNET_TIMEOUT: u64 = 43200; // 12 hours
const MONERO_UNLOCK: u64 = 10;       // 10 blocks (~20 min)

// Safety margin: 10 blocks + 1 hour buffer
assert!(STARKNET_TIMEOUT > (MONERO_UNLOCK * 120) + 3600);
```

### 3. Key Image Verification

```rust
// ALWAYS verify key images to prevent double-spending
let tx_info = wallet.get_transfer_by_txid(&tx_hash).await?;

// Store key image in your database
db.store_key_image(&tx_hash, &tx_info)?;

// Check before accepting XMR
if db.key_image_exists(&tx_info) {
    return Err("Double-spend attempt detected!");
}
```

## Performance Metrics (Stagenet)

| Operation | Expected Time | Notes |
|-----------|---------------|-------|
| Connection check | <1 second | `get_version()` |
| Create transaction | 1-3 seconds | `transfer_locked()` |
| First confirmation | ~2 minutes | Average block time |
| 10 confirmations | ~20 minutes | COMIT production standard |
| Timelock unlock | Variable | Depends on height delta |

## References

- [COMIT Network xmr-btc-swap](https://github.com/comit-network/xmr-btc-swap)
- [Monero Wallet RPC Docs](https://www.getmonero.org/resources/developer-guides/wallet-rpc.html)
- [Atomic Swap Research Paper](https://arxiv.org/abs/2101.12332)
- [Stagenet Explorer](https://stagenet.xmrchain.net/)

## Support

Issues with Monero integration? Check:

1. `rust/tests/wallet_integration_test.rs` - Working examples
2. `rust/src/monero_wallet/client.rs` - Implementation
3. COMIT Network repo - Production reference


