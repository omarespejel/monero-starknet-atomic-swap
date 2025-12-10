#!/bin/bash
set -e

echo "=== Deployer Account Setup ==="
echo ""

# Step 1: Initialize account
echo "Step 1: Initializing account..."
echo "You will be prompted for the keystore password."
starkli account oz init \
  --keystore ~/.starkli-wallets/deployer/keystore.json \
  ~/.starkli-wallets/deployer/account.json

# Step 2: Extract address
echo ""
echo "Step 2: Extracting account address..."
ACCOUNT_ADDRESS=$(cat ~/.starkli-wallets/deployer/account.json | grep -o '"address":"[^"]*"' | head -1 | cut -d'"' -f4)

if [ -z "$ACCOUNT_ADDRESS" ]; then
  echo "❌ Could not extract account address"
  exit 1
fi

echo ""
echo "=========================================="
echo "✅ ACCOUNT ADDRESS FOR FUNDING:"
echo "=========================================="
echo "$ACCOUNT_ADDRESS"
echo ""
echo "Fund this address at:"
echo "https://starknet-faucet.vercel.app/"
echo ""
echo "After funding, deploy the account with:"
echo "starkli account deploy \\"
echo "  --keystore ~/.starkli-wallets/deployer/keystore.json \\"
echo "  ~/.starkli-wallets/deployer/account.json \\"
echo "  --rpc https://api.zan.top/public/starknet-sepolia"
echo "=========================================="

