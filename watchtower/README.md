# Atomic Swap Watchtower

Monitoring service for XMR↔Starknet atomic swaps.

## Features

- **Event Monitoring**: Listens for `SecretRevealed` and `TokensClaimed` events
- **Grace Period Tracking**: Alerts when grace period is about to expire
- **Multi-Channel Alerts**: Discord, Telegram support
- **Monero Integration**: Monitor confirmations and reorgs
- **Relayer (RPC)**: Optionally calls `reveal_secret` after confirmations

## Configuration

Create a `.env` file (see `.env.example`):

```
# Starknet RPC (ZAN public endpoint - recommended)
STARKNET_RPC_URL=https://api.zan.top/public/starknet-sepolia

# Alternative endpoints:
# - https://starknet-sepolia.public.blastapi.io
# - https://free-rpc.nethermind.io/sepolia-juno

# Discord Alerts (optional)
DISCORD_WEBHOOK=https://discord.com/api/webhooks/...

# Telegram Alerts (optional)
TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
TELEGRAM_CHAT_ID=-100123456789

# Contracts to monitor (comma-separated hex addresses)
WATCHED_CONTRACTS=0x123...,0x456...

# Monero daemon RPC (required for relayer)
MONERO_DAEMON_URL=http://localhost:18081/json_rpc

# Swap registry (persistent)
SWAP_REGISTRY_PATH=watchtower_swaps.json

# Health endpoint
HEALTH_ADDR=127.0.0.1:8080

# Relayer (optional - enable by setting RELAY_CONTRACT_ADDRESS)
RELAY_CONTRACT_ADDRESS=0xATOMIC_LOCK
RELAY_SECRET_HEX=0x<64-hex-bytes>
RELAY_MONERO_TXID=<txid>
RELAY_ACCOUNT_ADDRESS=0xACCOUNT
RELAY_PRIVATE_KEY=0xPRIVATE_KEY
RELAY_ATOMIC_LOCK_CLASS_HASH=0xCLASS_HASH
RELAY_CHAIN_ID=0x534e5f5345504f4c4941
RELAY_CONFIRMATIONS=10
RELAY_POLL_INTERVAL_SECS=20
RELAY_STARKNET_RPC_URL=https://api.zan.top/public/starknet-sepolia

# Relayer file (optional)
RELAY_SWAPS_PATH=relay_swaps.json
```

## Usage

```
# Build
cargo build --release

# Run
cargo run --release
```

## Relayer Mode (RPC)

When `RELAY_CONTRACT_ADDRESS` is set, watchtower will:
1) Wait for `RELAY_MONERO_TXID` to reach `RELAY_CONFIRMATIONS`
2) Call `reveal_secret` on Starknet using the configured account

This is a deployable Phase‑1 relayer (trusted RPC). It does not provide on‑chain
Monero verification.

You can also provide multiple relay targets via `RELAY_SWAPS_PATH`:

```json
{
  "defaults": {
    "starknet_rpc": "https://api.zan.top/public/starknet-sepolia",
    "account_address": "0xACCOUNT",
    "private_key": "0xPRIVATE_KEY",
    "atomic_lock_class_hash": "0xCLASS_HASH",
    "chain_id": "0x534e5f5345504f4c4941",
    "confirmations": 10,
    "poll_interval_secs": 20
  },
  "swaps": [
    {
      "contract_address": "0xATOMIC_LOCK",
      "secret_hex": "0x<64-hex-bytes>",
      "monero_txid": "<txid>"
    }
  ]
}
```

## Alert Types

| Event | Alert Level | Description |
|-------|-------------|-------------|
| Secret Revealed | Info | Grace period started |
| Grace Period Warning | Warning | 30 min before expiry |
| Grace Period Expired | Critical | Tokens now claimable |
| Tokens Claimed | Info | Swap completed |
| Monero Unconfirmed | Critical | XMR TX not confirmed in grace period |

## Architecture

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────┐
│ Starknet RPC    │───▶│ Event Listener   │───▶│ Alert Queue │
└─────────────────┘    └──────────────────┘    └──────┬──────┘
                                                      │
┌─────────────────┐    ┌──────────────────┐          │
│ Monero Node     │───▶│ TX Watcher       │──────────┤
└─────────────────┘    └──────────────────┘          │
                                                      ▼
                       ┌──────────────────┐    ┌─────────────┐
                       │ Discord/Telegram │◀───│ Notifier    │
                       └──────────────────┘    └─────────────┘
```

## Status

**Current Status**: Skeleton implementation

**Status**: Event selectors and parsing implemented ✅

**TODO**:
- [x] Compute event selectors from Cairo contract
- [x] Implement event parsing (SecretRevealed, TokensClaimed)
- [x] Add grace period warning scheduler
- [x] Implement Monero watcher (daemon RPC)
- [x] Optional relayer (RPC-based reveal)
- [ ] Add database for state persistence
- [ ] Add health check endpoint
- [ ] Deploy and test on Sepolia testnet

## Development

```bash
# Run tests
cargo test

# Run with logging
RUST_LOG=info cargo run
```

## Service Templates

- `atomic-swap-watchtower.service` (systemd)
- `atomic-swap-watchtower.plist` (launchd)

