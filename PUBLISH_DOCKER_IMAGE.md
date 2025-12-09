# Publishing Monero Wallet RPC Docker Image

## Overview

The Docker setup we've created is production-ready and could be published as a standalone Docker image for the community. This would help other developers avoid the common pitfalls we encountered.

## Current Setup

Our `Dockerfile.wallet-rpc` provides:
- ✅ Official Monero v0.18.3.1 binaries
- ✅ Proper x86_64 architecture support (works on ARM64 via emulation)
- ✅ Minimal Ubuntu base image
- ✅ Production-ready configuration
- ✅ Healthcheck support

## Publishing Options

### Option 1: Docker Hub (Recommended)

```bash
# Build and tag
docker build -f Dockerfile.wallet-rpc -t yourusername/monero-wallet-rpc:0.18.3.1 .
docker build -f Dockerfile.wallet-rpc -t yourusername/monero-wallet-rpc:latest .

# Push to Docker Hub
docker push yourusername/monero-wallet-rpc:0.18.3.1
docker push yourusername/monero-wallet-rpc:latest
```

**Benefits:**
- Easy for others to use: `docker pull yourusername/monero-wallet-rpc`
- Version tags for stability
- Public registry, widely accessible

### Option 2: GitHub Container Registry (ghcr.io)

```bash
# Build and tag
docker build -f Dockerfile.wallet-rpc -t ghcr.io/yourusername/monero-wallet-rpc:0.18.3.1 .
docker build -f Dockerfile.wallet-rpc -t ghcr.io/yourusername/monero-wallet-rpc:latest .

# Push to GHCR
docker push ghcr.io/yourusername/monero-wallet-rpc:0.18.3.1
docker push ghcr.io/yourusername/monero-wallet-rpc:latest
```

**Benefits:**
- Integrated with GitHub
- Free for public images
- Good for open-source projects

### Option 3: Multi-Architecture Build (Advanced)

For better ARM64 support without emulation:

```bash
# Install buildx
docker buildx create --use

# Build for multiple architectures
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -f Dockerfile.wallet-rpc \
  -t yourusername/monero-wallet-rpc:0.18.3.1 \
  --push .
```

**Note:** Requires ARM64 binaries from Monero, which may not be available for all versions.

## Improvements Over Existing Images

### Comparison with `sethsimmons/simple-monerod`

| Feature | Our Image | simple-monerod |
|---------|-----------|----------------|
| **wallet-rpc support** | ✅ Explicit | ⚠️ Designed for monerod |
| **Platform handling** | ✅ x86_64 with emulation | ⚠️ Architecture issues |
| **Configuration** | ✅ Production-ready flags | ⚠️ Basic setup |
| **Healthcheck** | ✅ Included | ❌ Missing |
| **Documentation** | ✅ Comprehensive | ⚠️ Minimal |

### Key Advantages

1. **Explicit wallet-rpc focus**: Designed specifically for wallet operations
2. **Better error handling**: Includes `--confirm-external-bind` flag
3. **Production config**: Proper logging, non-interactive mode
4. **Documentation**: Comprehensive setup guides included
5. **Tested**: Verified with integration tests

## Recommended Publishing Steps

1. **Create GitHub Release**
   ```bash
   git tag -a v0.18.3.1-docker -m "Docker image for Monero wallet-rpc v0.18.3.1"
   git push origin v0.18.3.1-docker
   ```

2. **Add GitHub Actions Workflow** (`.github/workflows/docker-publish.yml`)
   ```yaml
   name: Publish Docker Image
   
   on:
     push:
       tags:
         - 'v*-docker'
   
   jobs:
     build-and-push:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4
         - name: Build and push
           uses: docker/build-push-action@v5
           with:
             context: .
             file: ./Dockerfile.wallet-rpc
             push: true
             tags: |
               ghcr.io/${{ github.repository_owner }}/monero-wallet-rpc:latest
               ghcr.io/${{ github.repository_owner }}/monero-wallet-rpc:${{ github.ref_name }}
   ```

3. **Update README.md** with usage instructions:
   ```markdown
   ## Quick Start with Docker
   
   ```bash
   docker pull ghcr.io/yourusername/monero-wallet-rpc:latest
   docker run -d \
     -p 38088:38088 \
     -v wallet-data:/wallets \
     ghcr.io/yourusername/monero-wallet-rpc:latest \
     --stagenet \
     --daemon-address stagenet.xmr-tw.org:38081 \
     --rpc-bind-ip 0.0.0.0 \
     --rpc-bind-port 38088 \
     --disable-rpc-login \
     --confirm-external-bind
   ```
   ```

4. **Add to Docker Hub Description**:
   - Link to project repository
   - Usage examples
   - Configuration options
   - Troubleshooting tips

## Usage Example for Others

```bash
# Pull image
docker pull yourusername/monero-wallet-rpc:latest

# Run with docker-compose (recommended)
# Use the provided docker-compose.yml

# Or run directly
docker run -d \
  --name monero-wallet-rpc \
  -p 38088:38088 \
  -v monero-wallets:/wallets \
  yourusername/monero-wallet-rpc:latest \
  --stagenet \
  --daemon-address stagenet.xmr-tw.org:38081 \
  --rpc-bind-ip 0.0.0.0 \
  --rpc-bind-port 38088 \
  --disable-rpc-login \
  --wallet-dir /wallets \
  --confirm-external-bind
```

## Maintenance

- **Version Updates**: Update Dockerfile when new Monero versions are released
- **Security**: Regularly update base Ubuntu image
- **Documentation**: Keep README and examples up to date
- **Testing**: Run integration tests before publishing new versions

## License Considerations

- Monero binaries: GPL-3.0
- Dockerfile: Same as project license
- Ensure compliance with Monero's license

---

**Recommendation**: Yes, this Docker image is better than existing options and should be published. It solves real problems developers face when setting up Monero wallet-rpc for atomic swaps.

