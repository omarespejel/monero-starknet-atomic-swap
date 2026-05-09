# Setup Guide

Complete setup guide for Monero wallet-rpc, Starknet devnet, and Docker
deployment.

Security note: current swap rehearsals use a Linux VM for all Monero processes.
Do not run `monerod`, `monero-wallet-rpc`, or generated claim wallets directly
on macOS. Use the Lima VM runbook in `docs/RELAYER_OPERATIONS.md` for
claim-side relayer operations.

## Quick Start

### Monero Wallet RPC (Linux VM)

```bash
# Show VM status and wallet-rpc process
./scripts/monero_vm_tunnel.sh status

# Query the primary wallet from inside the VM
./scripts/monero_vm_tunnel.sh vm-address
./scripts/monero_vm_tunnel.sh vm-balance
```

### Starknet Devnet

```bash
# Using management script (recommended)
./scripts/devnet.sh start

# Check status
./scripts/devnet.sh status

# View logs
./scripts/devnet.sh logs

# Run connection test
./scripts/devnet.sh test

# Stop devnet
./scripts/devnet.sh stop
```

**Account (seed 0)**: `0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691`  
**Private Key**: `0x71d7bb07b9a64f6f78ac4c816aff4da9`

---

## Monero Wallet RPC Setup

### Option 1: Linux VM (Required For Swap Ops)

Use Lima or a dedicated Linux host. The active local VM name is
`monero-stagenet`; scripts default to that VM.

```bash
./scripts/monero_vm_tunnel.sh status
./scripts/monero_vm_tunnel.sh vm-height
./scripts/monero_vm_tunnel.sh vm-address
./scripts/monero_vm_tunnel.sh vm-balance
```

For the claim-side service, use:

```bash
cd rust
cargo build --release --bin claim_relayer_service
target/release/claim_relayer_service \
  --config /etc/atomic-swap/claim-relayer.config.json \
  --dry-run \
  --once
```

See `docs/RELAYER_OPERATIONS.md` for systemd service templates, cursor rules,
and stuck wallet-rpc triage.

### Option 2: Docker (Legacy Dev Only)

Docker remains useful for isolated development experiments, but it is not the
current path for funded stagenet/mainnet swap operations.

### Verification

```bash
./scripts/monero_vm_tunnel.sh vm-height
./scripts/monero_vm_tunnel.sh vm-address
./scripts/monero_vm_tunnel.sh vm-balance
```

### Funding Your Wallet (Stagenet)

1. Get your stagenet address from `./scripts/monero_vm_tunnel.sh vm-address`
2. Visit: https://stagenet-faucet.xmr-tw.org/
3. Enter address and request test XMR
4. Wait ~10 minutes for confirmation

### Running Integration Tests

```bash
cd rust

# Run all wallet integration tests
cargo test --test wallet_integration_test -- --ignored

# Run specific test
cargo test --test wallet_integration_test test_wallet_connection_and_balance -- --ignored --nocapture
```

---

## Starknet Devnet Setup

### Option 1: Management Script (Recommended)

```bash
# Start devnet
./scripts/devnet.sh start

# Check status
./scripts/devnet.sh status

# View logs
./scripts/devnet.sh logs

# Run connection test
./scripts/devnet.sh test

# Stop devnet
./scripts/devnet.sh stop
```

### Option 2: Docker Compose

```bash
# Start devnet
docker-compose up -d starknet-devnet

# View logs
docker-compose logs -f starknet-devnet

# Stop devnet
docker-compose stop starknet-devnet
```

### Option 3: Direct Docker Command

```bash
docker run -d \
  --name starknet-devnet \
  -p 5050:5050 \
  shardlabs/starknet-devnet-rs \
  --seed 0 \
  --port 5050 \
  --host 0.0.0.0
```

### Why Use `--seed 0`?

Provides deterministic pre-funded accounts:
- Same accounts every time (useful for CI/CD)
- Pre-funded with ETH for testing
- Account 0: `0x64b48806902a367c8598f4f95c305e8c1a1acba5f082d294a43793113115691`

### Verification

```bash
# Check devnet is running
curl http://127.0.0.1:5050/is_alive

# Test RPC connection
curl -X POST http://127.0.0.1:5050/rpc \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "starknet_getBlockWithTxHashes",
    "params": {"block_id": "latest"}
  }'

# Run Rust E2E tests
cd rust
cargo test --test devnet_e2e_test -- --ignored --nocapture
```

---

## Docker Publishing

### Publishing to Docker Hub

```bash
# Login
docker login

# Tag images
docker tag monero-wallet-rpc:latest yourusername/monero-wallet-rpc:latest

# Push
docker push yourusername/monero-wallet-rpc:latest
```

### Publishing to GitHub Container Registry

The GitHub Actions workflow automatically publishes on tags:

```bash
# Create tag (optional)
git tag -a docker-latest -m "Latest Docker image"
git push origin docker-latest
```

The workflow builds and pushes to `ghcr.io/yourusername/monero-wallet-rpc`.

### Manual Publishing to GHCR

```bash
# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u yourusername --password-stdin

# Tag and push
docker tag monero-wallet-rpc:latest ghcr.io/yourusername/monero-wallet-rpc:latest
docker push ghcr.io/yourusername/monero-wallet-rpc:latest
```

---

## Rust Integration

### Core Functions

**Create Locked Transaction**:
```rust
let amount_piconero = 100_000_000_000; // 0.1 XMR
let result = wallet.transfer_locked(
    &destination_address,
    amount_piconero,
    unlock_height, // Block height when funds unlock
).await?;
```

**Wait for Confirmations** (10-block standard):
```rust
wallet.wait_for_confirmations(&tx_hash, 10).await?;
```

**Verify Key Image**:
```rust
let tx_info = wallet.get_transfer_by_txid(&tx_hash).await?;
assert!(tx_info.confirmations >= 10);
```

### Testing Strategy

1. **Connection Test** (5 seconds): `cargo test test_wallet_connection_and_balance -- --ignored`
2. **Transaction Test** (~5 minutes): `cargo test test_locked_transaction_creation -- --ignored`
3. **Production Safety** (~20 minutes): `cargo test test_ten_confirmation_safety -- --ignored`
4. **Refund Scenario** (~10 minutes): `cargo test test_refund_scenario -- --ignored`

---

## Troubleshooting

### Monero Wallet RPC

**Port Already in Use**:
```bash
limactl shell monero-stagenet -- sh -lc "ss -ltnp | grep 3809 || true"
```

**Can't Connect to Daemon**:
- Check the VM process list: `./scripts/monero_vm_tunnel.sh status`
- Check the primary wallet: `./scripts/monero_vm_tunnel.sh vm-height`
- Restart only the claim wallet-rpc service if the claim relayer is stuck; do
  not stop the funded primary wallet-rpc unless you are explicitly rotating it.

**Legacy Container Not Starting**:
```bash
docker logs monero-wallet-rpc
docker-compose restart
```

### Starknet Devnet

**Port Already in Use**:
```bash
lsof -i :5050
./scripts/devnet.sh stop
```

**Devnet Not Responding**:
```bash
./scripts/devnet.sh restart
./scripts/devnet.sh logs
```

---

## Production Considerations

### Monero Wallet RPC

- Use mainnet (remove `--stagenet` flag)
- Enable authentication (`--rpc-login` instead of `--disable-rpc-login`)
- Use your own daemon (not public nodes)
- Set up SSL/TLS proxy for encrypted connections
- Restrict RPC port access with firewall
- Regularly backup wallet files

### Security

- Never hardcode passwords (use environment variables)
- Verify key images to prevent double-spending
- Coordinate timelocks: Monero must unlock BEFORE Starknet expires
- Store key images in database and check before accepting XMR

---

## Related Documentation

- `docs/PROTOCOL.md` - Protocol specification
- `docs/ARCHITECTURE.md` - System architecture
- `docs/AUDIT_DEPENDENCIES.md` - Dependency audit information
