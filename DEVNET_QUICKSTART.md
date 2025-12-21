# Starknet Devnet Quick Start Guide

## 🚀 Modern Approaches (Recommended)

### Option 1: Using the Script (Easiest)

```bash
# Start devnet
./scripts/devnet.sh start

# Check status
./scripts/devnet.sh status

# View logs
./scripts/devnet.sh logs

# Stop devnet
./scripts/devnet.sh stop

# Test connection
./scripts/devnet.sh test
```

### Option 2: Using Make (Convenient)

```bash
# Start devnet
make devnet-start

# Check status
make devnet-status

# View logs
make devnet-logs

# Stop devnet
make devnet-stop

# Test connection
make devnet-test
```

### Option 3: Using Docker Compose (Best for Multi-Service)

```bash
# Start devnet (and wallet-rpc)
docker-compose up -d starknet-devnet

# View logs
docker-compose logs -f starknet-devnet

# Stop devnet
docker-compose stop starknet-devnet

# Check status
docker-compose ps starknet-devnet
```

### Option 4: Direct Docker (Manual - Not Recommended)

```bash
# Only use if you need custom configuration
docker run -d \
  --name starknet-devnet \
  -p 5050:5050 \
  shardlabs/starknet-devnet-rs \
  --seed 0 \
  --port 5050 \
  --host 0.0.0.0
```

---

## 📋 Pre-Funded Accounts (Seed 0)

When using `--seed 0`, these accounts are pre-funded:

| Account | Address | Private Key |
|---------|---------|------------|
| Account 0 | `0x049a5a5c30836ff78b3f9a2c0868eaabeeb1ca8ea049d2ed435ad42fd6315fba` | `0x000000000000000000000000000000001e010f076fad70290a3d89c1ec9dd269` |
| Account 1 | `0x02af4cdbeb67c938c5fcdb354c5708e7d7c87e6acc868859a011bcb38473fb9e` | `0x00000000000000000000000000000000e132b5e8842126aa80a5943611177a1c` |

**Initial Balance**: 1000000000000000000000 WEI and FRI per account

---

## 🔧 Configuration

### Environment Variables

```bash
# Use different seed for different accounts
export DEVNET_SEED=1
./scripts/devnet.sh start

# Or inline
DEVNET_SEED=1 make devnet-start
```

### RPC URL

Default: `http://127.0.0.1:5050`

---

## ✅ Quick Health Check

```bash
# Check if devnet is running
curl http://127.0.0.1:5050/is_alive

# Get chain ID
curl -X POST http://127.0.0.1:5050/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"starknet_chainId"}'

# Get latest block
curl -X POST http://127.0.0.1:5050/rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":1,"method":"starknet_getBlockWithTxHashes","params":{"block_id":"latest"}}'
```

---

## 🎯 Recommended Workflow

```bash
# 1. Start devnet
make devnet-start

# 2. Verify it's running
make devnet-status

# 3. Use in your code/tests
# RPC URL: http://127.0.0.1:5050

# 4. View logs if needed
make devnet-logs

# 5. Stop when done
make devnet-stop
```

---

## 📝 Notes

- **Seed 0**: Deterministic accounts (same every time) - **Recommended for testing**
- **Port**: 5050 (default)
- **Chain ID**: SN_SEPOLIA (0x534e5f5345504f4c4941)
- **Predeployed Contracts**: UDC, FeeToken (ETH, STRK)
- **Accounts**: 10 pre-funded accounts with seed 0

---

## 🐛 Troubleshooting

```bash
# If devnet won't start
docker ps -a | grep starknet-devnet
docker rm -f starknet-devnet  # Remove old container
make devnet-start              # Start fresh

# Check logs
make devnet-logs

# Verify port isn't in use
lsof -i :5050
```
