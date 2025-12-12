#!/bin/bash
set -e

echo "=== Deploy AtomicLock Contract with sncast ==="
echo ""

# Check if sncast is installed
if ! command -v sncast &> /dev/null; then
  echo "❌ sncast not found. Installing Starknet Foundry..."
  echo ""
  echo "Install with:"
  echo "  curl -L https://raw.githubusercontent.com/foundry-rs/starknet-foundry/master/scripts/install.sh | sh"
  echo "  export PATH=\"\$HOME/.local/share/starknet-foundry/bin:\$PATH\""
  echo ""
  exit 1
fi

echo "✅ sncast found: $(sncast --version)"
echo ""

# RPC URL - Alchemy v0.10 (compatible with sncast)
RPC_URL="${STARKNET_RPC_URL:-https://starknet-sepolia.g.alchemy.com/starknet/version/rpc/v0_10/cf52O0RwFy1mEB0uoYsel}"
echo "📡 Using RPC: $RPC_URL"
echo ""

# Account name
ACCOUNT_NAME="deployer"

# Change to cairo directory
cd cairo

# Check if account exists
if [ ! -f "snfoundry.toml" ]; then
  echo "❌ snfoundry.toml not found. Run deploy_account_with_sncast.sh first"
  exit 1
fi

# Check if contract is compiled
CONTRACT_CLASS="target/dev/atomic_lock_AtomicLock.contract_class.json"
if [ ! -f "$CONTRACT_CLASS" ]; then
  echo "📦 Contract not compiled. Building..."
  scarb build
fi

if [ ! -f "$CONTRACT_CLASS" ]; then
  echo "❌ Contract build failed"
  exit 1
fi

echo "✅ Contract compiled"
echo ""

# Declare contract
echo "📄 Declaring contract..."
echo ""

if sncast declare \
  --contract-name "atomic_lock_AtomicLock" \
  --max-fee 100000000000000 \
  --url "$RPC_URL" 2>&1 | tee /tmp/sncast_declare.log; then
  echo ""
  echo "✅ Contract declared!"
  
  # Extract class hash
  CLASS_HASH=$(grep -oE 'class_hash: 0x[a-fA-F0-9]{64}' /tmp/sncast_declare.log | head -1 | grep -oE '0x[a-fA-F0-9]{64}' || echo "")
  
  if [ -n "$CLASS_HASH" ]; then
    echo "   Class Hash: $CLASS_HASH"
  fi
else
  # Check if already declared
  if grep -qi "already declared" /tmp/sncast_declare.log 2>/dev/null; then
    echo ""
    echo "✅ Contract already declared"
    CLASS_HASH=$(grep -oE '0x[a-fA-F0-9]{64}' /tmp/sncast_declare.log | head -1 || echo "")
    if [ -n "$CLASS_HASH" ]; then
      echo "   Class Hash: $CLASS_HASH"
    fi
  else
    echo ""
    echo "❌ Contract declaration failed"
    echo "   Check /tmp/sncast_declare.log for details"
    exit 1
  fi
fi

echo ""
echo "📋 Next steps:"
echo "  1. Generate deployment calldata:"
echo "     python3 tools/generate_deploy_calldata.py"
echo ""
echo "  2. Deploy contract instance with sncast:"
echo "     sncast deploy --class-hash $CLASS_HASH --constructor-calldata <calldata> --url $RPC_URL"
echo ""
echo "Or use the TypeScript script for deployment (once fee estimation is fixed)"

cd ..

