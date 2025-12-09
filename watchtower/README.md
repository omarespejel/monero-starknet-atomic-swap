# Atomic Swap Watchtower

Monitoring service for XMR↔Starknet atomic swaps.

## Features

- **Event Monitoring**: Listens for `SecretRevealed` and `TokensClaimed` events
- **Grace Period Tracking**: Alerts when grace period is about to expire
- **Multi-Channel Alerts**: Discord, Telegram support
- **Monero Integration**: (TODO) Monitor Monero transaction confirmations

## Configuration

Create a `.env` file:

```
# Starknet RPC
STARKNET_RPC_URL=https://starknet-sepolia.public.blastapi.io

# Discord Alerts (optional)
DISCORD_WEBHOOK=https://discord.com/api/webhooks/...

# Telegram Alerts (optional)
TELEGRAM_BOT_TOKEN=123456:ABC-DEF...
TELEGRAM_CHAT_ID=-100123456789

# Contracts to monitor (comma-separated)
WATCHED_CONTRACTS=0x123...,0x456...
```

## Usage

```
# Build
cargo build --release

# Run
cargo run --release
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

**TODO**:
- [ ] Compute event selectors from Cairo contract
- [ ] Implement Monero watcher (requires monero-rs integration)
- [ ] Add configuration file support
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

