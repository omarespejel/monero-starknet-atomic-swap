# Docker Setup Guide - Monero Wallet RPC

## Overview

This guide covers setting up Monero wallet-rpc using Docker, which provides isolation and avoids antivirus false positives.

**Published Image**: [`espejelomar/monero-wallet-rpc`](https://hub.docker.com/r/espejelomar/monero-wallet-rpc) on Docker Hub

## Quick Start

```bash
# Start wallet-rpc container
docker-compose up -d

# Check status
docker ps | grep monero-wallet-rpc

# View logs
docker logs -f monero-wallet-rpc

# Test connection
curl -X POST http://localhost:38088/json_rpc \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","id":"0","method":"get_version"}'
```

## Why Docker?

### Benefits

1. **Antivirus Isolation**: Monero binaries often trigger false positives. Docker provides complete isolation.
2. **Easy Setup**: One command vs manual compilation and configuration.
3. **Consistency**: Same environment across dev/staging/production.
4. **Portability**: Works on any system with Docker (Mac, Linux, Windows).

### Architecture Support

- **x86_64**: Native support
- **ARM64 (Apple Silicon)**: Works via x86_64 emulation
- **Platform**: `linux/amd64` (forced in docker-compose.yml)

## Configuration

### docker-compose.yml

The setup uses a custom Dockerfile with official Monero binaries:

```yaml
services:
  monero-wallet-rpc:
    platform: linux/amd64
    build:
      context: .
      dockerfile: Dockerfile.wallet-rpc
    ports:
      - "38088:38088"
    volumes:
      - wallet-data:/wallets
    restart: unless-stopped
```

### Key Configuration Flags

- `--stagenet`: Use Monero testnet
- `--daemon-address stagenet.xmr-tw.org:38081`: Public stagenet daemon
- `--rpc-bind-ip 0.0.0.0`: Allow external connections
- `--rpc-bind-port 38088`: RPC port
- `--disable-rpc-login`: No authentication (for testing)
- `--confirm-external-bind`: Required flag for external binding
- `--wallet-dir /wallets`: Persistent wallet storage
- `--log-level 2`: Info level logging
- `--non-interactive`: Run in background

## Troubleshooting

### Container Keeps Restarting

**Problem**: Container exits immediately after starting.

**Solutions**:
1. Check logs: `docker logs monero-wallet-rpc`
2. Ensure `--confirm-external-bind` flag is present
3. Verify platform is set to `linux/amd64` in docker-compose.yml

### Connection Refused

**Problem**: Can't connect to wallet-rpc on port 38088.

**Solutions**:
1. Verify container is running: `docker ps | grep monero-wallet-rpc`
2. Check port mapping: `docker port monero-wallet-rpc`
3. Test from inside container: `docker exec monero-wallet-rpc curl http://localhost:38088/json_rpc`

### Permission Denied on Push

**Problem**: `docker push` fails with "denied: requested access to the resource is denied".

**Solution**: Ensure you're logged in with the correct Docker Hub username:
```bash
docker login
# Use the same username as in the image tag
```

## Development History

### Initial Issues

The original setup attempted to use `sethsimmons/simple-monerod`, but this image is designed for `monerod` (daemon), not `monero-wallet-rpc`. The container kept restarting because:
- The entrypoint script didn't properly handle wallet-rpc commands
- Architecture compatibility issues on ARM64

### Solution

Created a custom `Dockerfile.wallet-rpc` that:
- Uses official Monero v0.18.3.1 Linux binaries
- Properly installs `monero-wallet-rpc` to `/usr/local/bin`
- Sets correct entrypoint and default arguments
- Handles x86_64 binaries on ARM64 via emulation

### Current Status

✅ **Working**: Docker setup is production-ready and tested
✅ **Published**: Available on Docker Hub as `espejelomar/monero-wallet-rpc`
✅ **Documented**: Comprehensive guides and examples

## Alternative: Local Binary Setup

If Docker isn't available, see `docs/SETUP.md` for local binary setup instructions.

## Production Deployment

For production deployment, consider:
1. Using mainnet (remove `--stagenet` flag)
2. Enabling RPC authentication (`--rpc-login` instead of `--disable-rpc-login`)
3. Using your own Monero daemon (not public nodes)
4. Setting up SSL/TLS proxy for encrypted connections
5. Using Docker secrets for sensitive configuration

## Related Documentation

- `docs/SETUP.md`: Complete setup guide (Docker + local binary)
- `docs/DOCKER_PUBLISHING.md`: Publishing Docker images

