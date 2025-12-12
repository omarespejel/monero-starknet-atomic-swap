#!/bin/bash
set -e

echo "=== Deploy Account Contract with sncast (Starknet Foundry) ==="
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

# Load private key from .deployer_key
KEY_FILE=".deployer_key"
if [ ! -f "$KEY_FILE" ]; then
  echo "❌ Private key file not found: $KEY_FILE"
  echo "Run the TypeScript deployment script first to generate a key"
  exit 1
fi

PRIVATE_KEY=$(cat "$KEY_FILE" | tr -d '\n')
echo "✅ Loaded private key from $KEY_FILE"

# RPC URL
RPC_URL="${STARKNET_RPC_URL:-https://api.zan.top/public/starknet-sepolia}"
echo "📡 Using RPC: $RPC_URL"
echo ""

# Account name
ACCOUNT_NAME="deployer"

# Change to cairo directory (where Scarb project is)
cd cairo

# Create snfoundry.toml if it doesn't exist
if [ ! -f "snfoundry.toml" ]; then
  echo "Creating snfoundry.toml..."
  cat > "snfoundry.toml" << EOF
[sncast]
account = "$ACCOUNT_NAME"
url = "$RPC_URL"
EOF
fi

echo "📋 Creating account with sncast..."
echo ""

# Create account using sncast with private key
# Note: sncast account create may prompt for password
# We'll use --add-profile to add it to snfoundry.toml
if sncast account create "$ACCOUNT_NAME" \
  --private-key "$PRIVATE_KEY" \
  --add-profile \
  --url "$RPC_URL" 2>&1 | tee /tmp/sncast_account_create.log; then
  echo ""
  echo "✅ Account created successfully!"
else
  # Check if account already exists
  if grep -qi "already exists\|duplicate" /tmp/sncast_account_create.log 2>/dev/null; then
    echo ""
    echo "✅ Account already exists, using existing account"
  else
    echo ""
    echo "⚠️  Account creation had issues"
    echo "   Check /tmp/sncast_account_create.log for details"
    echo "   Continuing anyway..."
  fi
fi

echo ""
echo "📋 Account Configuration:"
echo "   Account name: $ACCOUNT_NAME"
echo "   RPC: $RPC_URL"
echo ""

# Deploy account using sncast
echo "🚀 Deploying account contract..."
echo ""

# sncast account deploy command
if sncast account deploy \
  --name "$ACCOUNT_NAME" \
  --max-fee 100000000000000 \
  --url "$RPC_URL" 2>&1 | tee /tmp/sncast_account_deploy.log; then
  echo ""
  echo "✅ Account deployed successfully!"
  
  # Extract deployed address from output
  DEPLOYED_ADDRESS=$(grep -oE '0x[a-fA-F0-9]{64}' /tmp/sncast_account_deploy.log | head -1 || echo "")
  
  if [ -n "$DEPLOYED_ADDRESS" ]; then
    echo ""
    echo "Account Details:"
    echo "  Address: $DEPLOYED_ADDRESS"
  fi
  
  echo "  RPC: $RPC_URL"
  echo ""
  echo "✅ Account is ready! You can now use:"
  echo "   bun run deploy"
else
  echo ""
  # Check if account is already deployed
  if grep -qi "already deployed\|contract already exists" /tmp/sncast_account_deploy.log 2>/dev/null; then
    echo "✅ Account is already deployed!"
    echo ""
    echo "You can proceed with:"
    echo "   bun run deploy"
  else
    echo "⚠️  Account deployment may have failed"
    echo "   Check the output above for details"
    echo "   Log saved to: /tmp/sncast_account_deploy.log"
    echo ""
    echo "Common issues:"
    echo "  - Account class not declared (network issue)"
    echo "  - Insufficient balance"
    echo "  - RPC connection issues"
    echo ""
    echo "If the Account class is not declared, you may need to:"
    echo "  1. Use a pre-deployed account, or"
    echo "  2. Wait for the Account class to be declared on Sepolia"
  fi
fi

cd ..

