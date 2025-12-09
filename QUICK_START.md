# Quick Start Guide - Monero Wallet RPC

## Docker Setup (Recommended - Avoids Antivirus False Positives)

### Prerequisites
- Docker Desktop or Colima installed and running
- `docker-compose` available

### Start Wallet RPC

```bash
# Navigate to project root
cd /Users/espejelomar/StarkNet/monero-secret-gen

# Start wallet-rpc container
docker-compose up -d

# Check status
docker ps | grep monero-wallet-rpc

# View logs (follow mode)
docker logs -f monero-wallet-rpc
```

### Verify Connection

```bash
# Test version endpoint
curl -X POST http://localhost:38088/json_rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_version"}'

# Expected response:
# {
#   "id": "0",
#   "jsonrpc": "2.0",
#   "result": {
#     "release": true,
#     "version": 65562
#   }
# }
```

### Create a Test Wallet

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
  -d '{
    "jsonrpc":"2.0",
    "id":"0",
    "method":"get_address"
  }'
```

### Fund Your Wallet (Stagenet)

1. Get your stagenet address from the `get_address` call above
2. Visit: https://stagenet-faucet.xmr-tw.org/
3. Enter your address and request test XMR
4. Wait ~10 minutes for confirmation

### Run Integration Tests

```bash
cd rust

# Run all wallet integration tests
cargo test --test wallet_integration_test -- --ignored

# Run specific test
cargo test --test wallet_integration_test test_wallet_connection_and_balance -- --ignored --nocapture
```

## Troubleshooting

### Container Not Starting

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

### Connection Refused

```bash
# Verify container is running
docker ps | grep monero-wallet-rpc

# Check port mapping
docker port monero-wallet-rpc

# Test from inside container
docker exec monero-wallet-rpc curl http://localhost:38088/json_rpc
```

### Wallet Not Found

```bash
# List wallets in container
docker exec monero-wallet-rpc ls -la /wallets

# Create wallet (see above)
```

## Configuration

- **RPC Port**: `38088` (mapped to host)
- **Network**: Stagenet (testnet)
- **Public Daemon**: `stagenet.xmr-tw.org:38081`
- **Wallet Directory**: `/wallets` (persisted in Docker volume `wallet-data`)

## Stop Wallet RPC

```bash
# Stop container
docker-compose stop

# Stop and remove container
docker-compose down

# Stop and remove container + volumes (⚠️ deletes wallets)
docker-compose down -v
```

---

*For more details, see `DOCKER_SETUP_SUCCESS.md` and `rust/docs/MONERO_WALLET_INTEGRATION.md`*
