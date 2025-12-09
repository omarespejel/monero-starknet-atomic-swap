#!/bin/bash
# Publish Monero Wallet RPC to Docker Hub
# Usage: ./scripts/publish_dockerhub.sh

set -e

echo "🚀 Publishing Monero Wallet RPC to Docker Hub"
echo ""

# Check if logged in
if ! docker info | grep -q "Username"; then
    echo "⚠️  Not logged into Docker Hub"
    echo "   Please run: docker login"
    echo "   Or: docker login -u omarespejel"
    exit 1
fi

echo "✅ Logged into Docker Hub"
echo ""

# Push version tag
echo "📤 Pushing omarespejel/monero-wallet-rpc:0.18.3.1..."
docker push omarespejel/monero-wallet-rpc:0.18.3.1

# Push latest tag
echo ""
echo "📤 Pushing omarespejel/monero-wallet-rpc:latest..."
docker push omarespejel/monero-wallet-rpc:latest

echo ""
echo "✅ Successfully published to Docker Hub!"
echo ""
echo "📦 Images available at:"
echo "   https://hub.docker.com/r/omarespejel/monero-wallet-rpc"
echo ""
echo "💡 Usage:"
echo "   docker pull omarespejel/monero-wallet-rpc:latest"

