# Publishing Docker Images

## Overview

This guide covers publishing the Monero wallet-rpc Docker image to Docker Hub and GitHub Container Registry.

## Published Images

- **Docker Hub**: [`espejelomar/monero-wallet-rpc`](https://hub.docker.com/r/espejelomar/monero-wallet-rpc)
- **GitHub Container Registry**: `ghcr.io/omarespejel/monero-wallet-rpc`

## Quick Publish

### Using the Script

```bash
# 1. Login to Docker Hub
docker login

# 2. Run publishing script
./scripts/publish_dockerhub.sh
```

The script automatically detects your Docker Hub username and publishes both version and latest tags.

### Manual Publishing

```bash
# Tag images
docker tag monero-wallet-rpc:latest yourusername/monero-wallet-rpc:0.18.3.1
docker tag monero-wallet-rpc:latest yourusername/monero-wallet-rpc:latest

# Push to Docker Hub
docker push yourusername/monero-wallet-rpc:0.18.3.1
docker push yourusername/monero-wallet-rpc:latest
```

## Publishing to Docker Hub

### Prerequisites

1. Docker Hub account
2. Docker installed and running
3. Built image: `monero-wallet-rpc:latest`

### Steps

1. **Login**:
   ```bash
   docker login
   ```

2. **Tag with your username**:
   ```bash
   docker tag monero-wallet-rpc:latest yourusername/monero-wallet-rpc:0.18.3.1
   docker tag monero-wallet-rpc:latest yourusername/monero-wallet-rpc:latest
   ```

3. **Push**:
   ```bash
   docker push yourusername/monero-wallet-rpc:0.18.3.1
   docker push yourusername/monero-wallet-rpc:latest
   ```

### Using Access Token

For CI/CD or automated publishing:

1. Create access token: Docker Hub → Account Settings → Security → New Access Token
2. Use token instead of password:
   ```bash
   echo $DOCKER_HUB_TOKEN | docker login -u yourusername --password-stdin
   ```

## Publishing to GitHub Container Registry

### Automated (Recommended)

The GitHub Actions workflow automatically publishes on version tags:

```bash
# Create version tag
git tag -a v0.18.3.1-docker -m "Docker image v0.18.3.1"
git push origin v0.18.3.1-docker
```

The workflow will build and push to `ghcr.io/omarespejel/monero-wallet-rpc`.

### Manual Publishing

```bash
# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u yourusername --password-stdin

# Tag
docker tag monero-wallet-rpc:latest ghcr.io/yourusername/monero-wallet-rpc:0.18.3.1
docker tag monero-wallet-rpc:latest ghcr.io/yourusername/monero-wallet-rpc:latest

# Push
docker push ghcr.io/yourusername/monero-wallet-rpc:0.18.3.1
docker push ghcr.io/yourusername/monero-wallet-rpc:latest
```

## Image Details

### Current Version

- **Version**: v0.18.3.1
- **Size**: 104MB
- **Base**: Ubuntu 22.04
- **Monero**: Official v0.18.3.1 binaries
- **Architecture**: linux/amd64

### Tags

- `latest`: Always points to most recent version
- `0.18.3.1`: Specific version tag

## Advantages Over Alternatives

| Feature | Our Image | `sethsimmons/simple-monerod` |
|---------|-----------|------------------------------|
| wallet-rpc focus | ✅ Explicit | ⚠️ Designed for monerod |
| Production config | ✅ Ready | ⚠️ Basic |
| Healthcheck | ✅ Included | ❌ Missing |
| Documentation | ✅ Comprehensive | ⚠️ Minimal |
| ARM64 support | ✅ Works | ⚠️ Issues |

## Usage

The image is now published and available:

```bash
# Pull image
docker pull espejelomar/monero-wallet-rpc:latest

# Run container
docker run -d \
  -p 38088:38088 \
  -v wallet-data:/wallets \
  espejelomar/monero-wallet-rpc:latest \
  --stagenet \
  --daemon-address stagenet.xmr-tw.org:38081 \
  --rpc-bind-ip 0.0.0.0 \
  --rpc-bind-port 38088 \
  --disable-rpc-login \
  --confirm-external-bind
```

## Maintenance

### Updating Versions

1. Update `Dockerfile.wallet-rpc` with new Monero version
2. Build new image: `docker build -f Dockerfile.wallet-rpc -t monero-wallet-rpc:latest .`
3. Tag and push new version
4. Update documentation

### Version Tags

Follow semantic versioning:
- Major: Breaking changes
- Minor: New features
- Patch: Bug fixes

Example: `v0.18.3.1-docker` → `v0.18.3.2-docker` (patch)

## Related Documentation

- `docs/DOCKER_SETUP.md`: Using the Docker image
- `Dockerfile.wallet-rpc`: Image definition
- `.github/workflows/docker-publish.yml`: CI/CD workflow

