# Setup Guide - Monero Wallet RPC

Complete guide for setting up Monero wallet-rpc for atomic swap development and testing.

## Quick Start

### Option 1: Docker (Recommended)

**Benefits**: Avoids antivirus false positives, easy setup, consistent environment.

```bash
# Start wallet-rpc container
docker-compose up -d

# Check status
docker ps | grep monero-wallet-rpc

# View logs
docker logs -f monero-wallet-rpc

# Test connection
curl -X POST http://localhost:38088/json_rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_version"}'
```

See `docs/DOCKER_SETUP.md` for detailed Docker setup instructions.

### Option 2: Local Binary

**Prerequisites**: Mac (Intel or Apple Silicon), Terminal access, ~200MB disk space

#### Via Homebrew (Easiest)

```bash
brew install monero

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

#### Manual Download

**Mac (Apple Silicon)**:
```bash
curl -L -o monero-mac-arm8-v0.18.3.1.tar.bz2 \
  https://downloads.getmonero.org/cli/monero-mac-arm8-v0.18.3.1.tar.bz2
tar -xvf monero-mac-arm8-v0.18.3.1.tar.bz2
cd monero-aarch64-apple-darwin11-v0.18.3.1/
chmod +x monero-wallet-rpc
```

**Mac (Intel)**:
```bash
curl -L -o monero-mac-x64-v0.18.3.1.tar.bz2 \
  https://downloads.getmonero.org/cli/monero-mac-x64-v0.18.3.1.tar.bz2
tar -xvf monero-mac-x64-v0.18.3.1.tar.bz2
cd monero-x86_64-apple-darwin11-v0.18.3.1/
chmod +x monero-wallet-rpc
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

### Container Not Starting (Docker)

```bash
# Check logs
docker logs monero-wallet-rpc

# Restart container
docker-compose restart

# Rebuild if needed
docker-compose down
docker-compose build --no-cache
docker-compose up -d
```

### Connection Refused (Docker)

```bash
# Verify container is running
docker ps | grep monero-wallet-rpc

# Check port mapping
docker port monero-wallet-rpc

# Test from inside container
docker exec monero-wallet-rpc curl http://localhost:38088/json_rpc
```

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

- `docs/DOCKER_SETUP.md`: Detailed Docker setup guide
- `docs/DOCKER_PUBLISHING.md`: Publishing Docker images
- `rust/docs/MONERO_WALLET_INTEGRATION.md`: Rust client integration

