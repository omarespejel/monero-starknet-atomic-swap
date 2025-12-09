# Local Monero Wallet RPC Setup Instructions

## Quick Setup Guide

### Option A: Homebrew (Easiest - Recommended)

```bash
# Install Monero via Homebrew
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

### Option B: Manual Download

1. **Visit Monero Downloads Page:**
   - Go to: https://www.getmonero.org/downloads/
   - Select "Mac" and your architecture (Apple Silicon or Intel)
   - Download the CLI tools archive

2. **Extract and Run:**
   ```bash
   # Extract the downloaded archive
   tar -xvf monero-*.tar.bz2
   
   # Navigate to extracted directory
   cd monero-*/
   
   # Start wallet-rpc
   ./monero-wallet-rpc \
     --stagenet \
     --daemon-address stagenet.xmr-tw.org:38081 \
     --rpc-bind-port 38088 \
     --rpc-bind-ip 127.0.0.1 \
     --disable-rpc-login \
     --wallet-dir ../../wallets \
     --log-level 2
   ```

### Option C: Use Helper Script

```bash
cd /Users/espejelomar/StarkNet/monero-secret-gen
./start_wallet_rpc.sh
```

## Verify Setup

Once wallet-rpc is running, test the connection:

```bash
curl -X POST http://localhost:38088/json_rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_version"}'
```

Expected response:
```json
{"id":"0","jsonrpc":"2.0","result":{"version":...}}
```

## Run Tests

```bash
cd rust
cargo test --test wallet_integration_test test_wallet_connection_and_balance -- --ignored --nocapture
```

## Next Steps

1. Get your stagenet address from test output
2. Fund via: https://stagenet-faucet.xmr-tw.org/
3. Wait ~10 minutes for confirmation
4. Run full test suite

---

*Note: The direct download URL may change. Always check https://www.getmonero.org/downloads/ for the latest version.*


