# Publishing to Docker Hub - Quick Guide

## Status

✅ Images tagged:
- `omarespejel/monero-wallet-rpc:0.18.3.1`
- `omarespejel/monero-wallet-rpc:latest`

⏳ Waiting for Docker Hub login

## Steps to Complete Publishing

### 1. Login to Docker Hub

```bash
docker login
```

Or with username:
```bash
docker login -u omarespejel
```

You'll be prompted for your Docker Hub password or access token.

### 2. Push Images

Once logged in, run:

```bash
# Push version tag
docker push omarespejel/monero-wallet-rpc:0.18.3.1

# Push latest tag
docker push omarespejel/monero-wallet-rpc:latest
```

### 3. Verify

After pushing, verify on Docker Hub:
https://hub.docker.com/r/omarespejel/monero-wallet-rpc

## Alternative: Use Docker Hub Access Token

If you prefer using an access token (more secure):

1. Go to Docker Hub → Account Settings → Security → New Access Token
2. Create a token with "Read & Write" permissions
3. Use it instead of password:

```bash
echo $DOCKER_HUB_TOKEN | docker login -u omarespejel --password-stdin
```

## After Publishing

Once published, others can use:

```bash
docker pull omarespejel/monero-wallet-rpc:latest

docker run -d \
  -p 38088:38088 \
  -v wallet-data:/wallets \
  omarespejel/monero-wallet-rpc:latest \
  --stagenet \
  --daemon-address stagenet.xmr-tw.org:38081 \
  --rpc-bind-ip 0.0.0.0 \
  --rpc-bind-port 38088 \
  --disable-rpc-login \
  --confirm-external-bind
```

## Current Image Status

```bash
# Check tagged images
docker images | grep omarespejel/monero-wallet-rpc

# Expected output:
# omarespejel/monero-wallet-rpc   0.18.3.1   35d71dfbf37f   17 minutes ago   104MB
# omarespejel/monero-wallet-rpc   latest     35d71dfbf37f   17 minutes ago   104MB
```

---

**Note**: Images are ready to push. Just need Docker Hub authentication.

