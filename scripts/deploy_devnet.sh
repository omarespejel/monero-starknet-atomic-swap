#!/bin/bash
# Deploy AtomicLock contract to devnet using Starknet.js
# Assumes devnet is running at http://127.0.0.1:5050
# 
# This script uses the TypeScript deployment script which handles:
# - Account deployment (if needed)
# - Contract declaration
# - Contract instance deployment

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CAIRO_DIR="$ROOT_DIR/cairo"

echo "=== Deploy AtomicLock to Devnet ==="
echo ""

# Check if devnet is running
if ! curl -s http://127.0.0.1:5050/is_alive > /dev/null 2>&1; then
    echo "❌ Devnet is not running. Start it with: ./scripts/devnet.sh start"
    exit 1
fi

echo "✅ Devnet is running"
echo ""

# Use TypeScript deployment script (recommended for devnet)
echo "📄 Deploying using Starknet.js..."
echo ""

cd "$ROOT_DIR/scripts/ts"

# Check if node_modules exists
if [ ! -d "node_modules" ]; then
    echo "📦 Installing dependencies..."
    npm install
    echo ""
fi

# Run deployment
if npm run deploy:devnet; then
    echo ""
    echo "✅ Deployment complete!"
    echo "   Check deployments/devnet-result.json for details"
else
    echo ""
    echo "❌ Deployment failed"
    echo "   Check the error messages above"
    echo ""
    echo "Note: If account deployment fails, devnet accounts might need"
    echo "      to be deployed manually first using devnet's account endpoints."
    exit 1
fi

echo ""
