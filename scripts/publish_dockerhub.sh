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

# Detect Docker Hub username
DOCKER_USERNAME=$(docker info 2>/dev/null | grep "Username:" | awk '{print $2}' || echo "")
if [ -z "$DOCKER_USERNAME" ]; then
    echo "❌ Could not detect Docker Hub username"
    echo "   Please ensure you're logged in: docker login"
    exit 1
fi

echo "✅ Detected Docker Hub username: $DOCKER_USERNAME"
echo ""

# Tag images with correct username
echo "🏷️  Tagging images..."
docker tag monero-wallet-rpc:latest ${DOCKER_USERNAME}/monero-wallet-rpc:0.18.3.1
docker tag monero-wallet-rpc:latest ${DOCKER_USERNAME}/monero-wallet-rpc:latest

# Push version tag
echo "📤 Pushing ${DOCKER_USERNAME}/monero-wallet-rpc:0.18.3.1..."
docker push ${DOCKER_USERNAME}/monero-wallet-rpc:0.18.3.1

# Push latest tag
echo ""
echo "📤 Pushing ${DOCKER_USERNAME}/monero-wallet-rpc:latest..."
docker push ${DOCKER_USERNAME}/monero-wallet-rpc:latest

echo ""
echo "✅ Successfully published to Docker Hub!"
echo ""
echo "📦 Images available at:"
echo "   https://hub.docker.com/r/${DOCKER_USERNAME}/monero-wallet-rpc"
echo ""
echo "💡 Usage:"
echo "   docker pull ${DOCKER_USERNAME}/monero-wallet-rpc:latest"

