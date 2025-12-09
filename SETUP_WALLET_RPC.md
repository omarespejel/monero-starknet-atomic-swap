# Monero Wallet RPC Setup Guide

## ⚠️ Important Note

The Docker setup requires the Monero binaries to be properly configured. For immediate testing, **Option B (Local Binary)** is recommended.

## Quick Start Options

### Option A: Docker (Requires Image Configuration)

**Prerequisites:**
- Docker Desktop installed OR Colima running

**Start Docker:**

```bash
# If using Colima:
colima start

# If using Docker Desktop:
# Just start Docker Desktop application
```

**Start Services:**

```bash
cd /Users/espejelomar/StarkNet/monero-secret-gen
docker-compose up -d

# Check status
docker-compose ps

# View logs
docker-compose logs -f monero-wallet-rpc
```

**Wait for Sync:**
- First time: 30-60 minutes for daemon to sync
- Check sync status: `docker-compose logs monerod-stagenet | grep "Synchronized"`
- Once synced, wallet-rpc will be ready

### Option B: Local Binary (Alternative)

**Download Monero CLI:**

```bash
# Mac (Intel)
wget https://downloads.getmonero.org/cli/monero-mac-x64-v0.18.3.1.tar.bz2
tar -xvf monero-mac-x64-v0.18.3.1.tar.bz2
cd monero-x86_64-apple-darwin11-v0.18.3.1/

# Mac (Apple Silicon)
wget https://downloads.getmonero.org/cli/monero-mac-arm8-v0.18.3.1.tar.bz2
tar -xvf monero-mac-arm8-v0.18.3.1.tar.bz2
cd monero-aarch64-apple-darwin11-v0.18.3.1/
```

**Start wallet-rpc:**

```bash
# Terminal 1: Start daemon (optional - can use remote node)
./monerod --stagenet --detach

# Terminal 2: Start wallet-rpc
./monero-wallet-rpc \
  --stagenet \
  --daemon-address stagenet.xmr-tw.org:38081 \
  --rpc-bind-port 38088 \
  --rpc-bind-ip 127.0.0.1 \
  --disable-rpc-login \
  --wallet-dir ./wallets \
  --log-level 2
```

### Option C: Use Public Wallet-RPC (Not Recommended for Production)

Some public stagenet wallet-rpc services exist, but they're not recommended for production use due to security concerns.

## Verify Setup

**Test Connection:**

```bash
curl -X POST http://localhost:38088/json_rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_version"}'

# Should return: {"id":"0","jsonrpc":"2.0","result":{"version":...}}
```

**Run Tests:**

```bash
cd rust
cargo test --test wallet_integration_test test_wallet_connection_and_balance -- --ignored --nocapture
```

## Expected Output

**First Run (No Wallet):**
```
✅ Created new wallet
📍 Stagenet address: 5A1...
💰 Balance: 0.000000000000 XMR
⚠️  Wallet has no balance. Fund it to run transaction tests.
```

**After Funding:**
```
✅ Opened existing wallet
📍 Stagenet address: 5A1...
💰 Balance: 1.000000000000 XMR
🔓 Unlocked: 1.000000000000 XMR
```

## Fund Wallet

1. **Get Address:**
   - Run the connection test to get your stagenet address

2. **Visit Faucet:**
   - https://stagenet-faucet.xmr-tw.org/
   - Enter your address
   - Solve captcha
   - Receive 1 XMR

3. **Wait for Confirmation:**
   - ~10 minutes for first confirmation
   - Re-run test to verify balance

## Troubleshooting

### "Failed to connect to wallet-rpc"

- Check if wallet-rpc is running: `docker-compose ps` or check process
- Verify port 38088 is not in use: `lsof -i :38088`
- Check firewall settings

### "Daemon not synced"

- First sync takes 30-60 minutes
- Check logs: `docker-compose logs monerod-stagenet`
- Look for "Synchronized" message

### "Wallet has no balance"

- Fund via stagenet faucet
- Wait 10 minutes for confirmation
- Re-run test

## Next Steps

Once wallet-rpc is running and wallet is funded:

```bash
# Run all integration tests
cd rust
cargo test --test wallet_integration_test -- --ignored

# Run specific tests
cargo test --test wallet_integration_test test_locked_transaction_creation -- --ignored
cargo test --test wallet_integration_test test_ten_confirmation_safety -- --ignored
```

