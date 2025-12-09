# Monero Wallet RPC Setup Guide

## Overview

This guide covers setting up Monero wallet-rpc for atomic swap development and testing. Two options are available: Docker (recommended) or local binary.

## Option 1: Docker Setup (Recommended)

**Benefits**: Avoids antivirus false positives, easy setup, consistent environment.

See `docs/DOCKER_SETUP.md` for complete Docker setup instructions.

**Quick start**:
```bash
docker-compose up -d
```

## Option 2: Local Binary Setup

### Prerequisites

- Mac (Intel or Apple Silicon)
- Terminal access
- ~200MB disk space

### Installation Steps

#### Mac (Apple Silicon)

```bash
# Download Monero CLI
curl -L -o monero-mac-arm8-v0.18.3.1.tar.bz2 \
  https://downloads.getmonero.org/cli/monero-mac-arm8-v0.18.3.1.tar.bz2

# Extract
tar -xvf monero-mac-arm8-v0.18.3.1.tar.bz2

# Navigate to extracted directory
cd monero-aarch64-apple-darwin11-v0.18.3.1/

# Make executable
chmod +x monero-wallet-rpc
```

#### Mac (Intel)

```bash
# Download Monero CLI
curl -L -o monero-mac-x64-v0.18.3.1.tar.bz2 \
  https://downloads.getmonero.org/cli/monero-mac-x64-v0.18.3.1.tar.bz2

# Extract
tar -xvf monero-mac-x64-v0.18.3.1.tar.bz2

# Navigate to extracted directory
cd monero-x86_64-apple-darwin11-v0.18.3.1/

# Make executable
chmod +x monero-wallet-rpc
```

#### Via Homebrew (Easiest)

```bash
brew install monero
```

### Starting Wallet RPC

```bash
# Create wallets directory
mkdir -p wallets

# Start wallet-rpc
monero-wallet-rpc \
  --stagenet \
  --daemon-address stagenet.xmr-tw.org:38081 \
  --rpc-bind-port 38088 \
  --rpc-bind-ip 127.0.0.1 \
  --disable-rpc-login \
  --wallet-dir ./wallets \
  --log-level 2
```

### Using Helper Script

A helper script is provided for convenience:

```bash
./start_wallet_rpc.sh
```

## Verification

### Test Connection

```bash
curl -X POST http://localhost:38088/json_rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_version"}'
```

Expected response:
```json
{
  "id": "0",
  "jsonrpc": "2.0",
  "result": {
    "release": true,
    "version": 65562
  }
}
```

### Create Test Wallet

```bash
curl -X POST http://localhost:38088/json_rpc \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc":"2.0",
    "id":"0",
    "method":"create_wallet",
    "params":{
      "filename":"test_wallet",
      "password":"test123",
      "language":"English"
    }
  }'
```

### Get Wallet Address

```bash
curl -X POST http://localhost:38088/json_rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_address"}'
```

## Funding Your Wallet (Stagenet)

1. Get your stagenet address from the `get_address` call above
2. Visit: https://stagenet-faucet.xmr-tw.org/
3. Enter your address and request test XMR
4. Wait ~10 minutes for confirmation

## Running Integration Tests

Once wallet-rpc is running:

```bash
cd rust

# Run all wallet integration tests
cargo test --test wallet_integration_test -- --ignored

# Run specific test
cargo test --test wallet_integration_test test_wallet_connection_and_balance -- --ignored --nocapture
```

## Troubleshooting

### Port Already in Use

**Problem**: `bind: address already in use`

**Solution**: 
- Check if another wallet-rpc is running: `lsof -i :38088`
- Kill existing process or use different port: `--rpc-bind-port 38089`

### Can't Connect to Daemon

**Problem**: Wallet-rpc can't connect to stagenet daemon

**Solutions**:
1. Try alternative daemon: `--daemon-address monero-stagenet.exan.tech:38081`
2. Check daemon status: `curl http://stagenet.xmr-tw.org:38081/json_rpc -d '{"jsonrpc":"2.0","id":"0","method":"get_block_count"}'`
3. Use local daemon (see Monero documentation)

### Antivirus False Positives

**Problem**: Antivirus flags Monero binaries as "bitcoin miner"

**Solution**: Use Docker setup instead (see `docs/DOCKER_SETUP.md`)

## Configuration Options

### Network Selection

- **Stagenet** (testing): `--stagenet`
- **Mainnet** (production): Remove `--stagenet` flag

### Daemon Options

- **Public stagenet**: `--daemon-address stagenet.xmr-tw.org:38081`
- **Alternative**: `--daemon-address monero-stagenet.exan.tech:38081`
- **Local daemon**: `--daemon-address localhost:38081`

### Security Options

- **No authentication** (testing): `--disable-rpc-login`
- **With authentication** (production): `--rpc-login username:password`

### Logging

- **Info level**: `--log-level 2` (default)
- **Debug level**: `--log-level 4`
- **Minimal**: `--log-level 0`

## Production Considerations

For production deployment:

1. **Use mainnet**: Remove `--stagenet` flag
2. **Enable authentication**: Use `--rpc-login` instead of `--disable-rpc-login`
3. **Use your own daemon**: Don't rely on public nodes
4. **SSL/TLS**: Set up reverse proxy with SSL
5. **Firewall**: Restrict RPC port access
6. **Backup**: Regularly backup wallet files

## Related Documentation

- `docs/DOCKER_SETUP.md`: Docker-based setup
- `rust/docs/MONERO_WALLET_INTEGRATION.md`: Rust client integration
- `QUICK_START.md`: Quick reference guide

