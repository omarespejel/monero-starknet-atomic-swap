# Docker Setup Notes

## Issue Identified

The `sethsimmons/simple-monerod` Docker image appears to be designed primarily for running `monerod` (the daemon), not `monero-wallet-rpc`. The entrypoint script may not properly handle wallet-rpc commands.

## Current Status

**Docker Setup**: ⏸️ **Needs Alternative Image**

The current Docker image (`sethsimmons/simple-monerod`) is not working correctly for wallet-rpc. The container keeps restarting, suggesting the command format or executable location is incorrect.

## Recommended Solutions

### Option 1: Use Official Monero Docker Image (Recommended)

Create a custom Dockerfile based on official Monero binaries:

```dockerfile
FROM ubuntu:22.04

RUN apt-get update && \
    apt-get install -y wget bzip2 curl && \
    wget https://downloads.getmonero.org/cli/monero-linux-x64-v0.18.3.1.tar.bz2 && \
    tar -xvf monero-linux-x64-v0.18.3.1.tar.bz2 && \
    cp monero-x86_64-linux-gnu-v0.18.3.1/monero-wallet-rpc /usr/local/bin/ && \
    rm -rf monero-* && \
    apt-get clean

EXPOSE 38088

ENTRYPOINT ["monero-wallet-rpc"]
```

### Option 2: Use Local Binary (Fastest for Testing)

For immediate testing, use the local Monero binary approach documented in `QUICK_START.md`. This is the fastest path to get tests running.

### Option 3: Alternative Docker Image

Search Docker Hub for alternative Monero wallet-rpc images:
- `monero-wallet-rpc` (if available)
- `monero/wallet-rpc` (if available)
- Build custom image from official binaries

## Next Steps

1. **For Immediate Testing**: Use local binary (see `QUICK_START.md`)
2. **For Production**: Build custom Docker image with official Monero binaries
3. **Alternative**: Find/verify working Docker image for wallet-rpc

## Current docker-compose.yml Status

The current `docker-compose.yml` is configured but not working due to image limitations. It's ready to use once we have a proper wallet-rpc image.

---

*Status: Docker setup blocked by image limitations. Local binary recommended for immediate testing.*


