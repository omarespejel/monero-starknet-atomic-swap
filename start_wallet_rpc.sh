#!/bin/bash
# Start Monero wallet-rpc for stagenet testing
# This script helps start wallet-rpc with the correct parameters

set -e

echo "🔧 Monero Wallet RPC Starter"
echo "============================"
echo ""

# Check if monero-wallet-rpc exists
MONERO_BIN=""
if command -v monero-wallet-rpc &> /dev/null; then
    MONERO_BIN="monero-wallet-rpc"
    echo "✅ Found monero-wallet-rpc in PATH"
elif [ -f "./monero-wallet-rpc" ]; then
    MONERO_BIN="./monero-wallet-rpc"
    echo "✅ Found monero-wallet-rpc in current directory"
elif [ -d "./monero-aarch64-apple-darwin11-v0.18.3.1" ]; then
    MONERO_BIN="./monero-aarch64-apple-darwin11-v0.18.3.1/monero-wallet-rpc"
    echo "✅ Found monero-wallet-rpc in extracted directory"
elif [ -d "./monero-x86_64-apple-darwin11-v0.18.3.1" ]; then
    MONERO_BIN="./monero-x86_64-apple-darwin11-v0.18.3.1/monero-wallet-rpc"
    echo "✅ Found monero-wallet-rpc in extracted directory"
else
    echo "❌ monero-wallet-rpc not found!"
    echo ""
    echo "Please download Monero CLI:"
    echo "  Mac (Apple Silicon):"
    echo "    wget https://downloads.getmonero.org/cli/monero-mac-arm8-v0.18.3.1.tar.bz2"
    echo "    tar -xvf monero-mac-arm8-v0.18.3.1.tar.bz2"
    echo ""
    echo "  Mac (Intel):"
    echo "    wget https://downloads.getmonero.org/cli/monero-mac-x64-v0.18.3.1.tar.bz2"
    echo "    tar -xvf monero-mac-x64-v0.18.3.1.tar.bz2"
    echo ""
    exit 1
fi

# Create wallets directory if it doesn't exist
mkdir -p wallets

echo ""
echo "🚀 Starting monero-wallet-rpc..."
echo "   Daemon: stagenet.xmr-tw.org:38081"
echo "   RPC Port: 38088"
echo "   Wallet Dir: ./wallets"
echo ""
echo "Press Ctrl+C to stop"
echo ""

# Start wallet-rpc
$MONERO_BIN \
  --stagenet \
  --daemon-address stagenet.xmr-tw.org:38081 \
  --rpc-bind-port 38088 \
  --rpc-bind-ip 127.0.0.1 \
  --disable-rpc-login \
  --wallet-dir ./wallets \
  --log-level 2


