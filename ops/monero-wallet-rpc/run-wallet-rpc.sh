#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    printf 'Missing required environment variable: %s\n' "$name" >&2
    exit 2
  fi
}

MONERO_WALLET_RPC_BIN="${MONERO_WALLET_RPC_BIN:-/opt/monero-starknet-atomic-swap/monero-bin/monero-wallet-rpc}"
MONERO_NETWORK="${MONERO_NETWORK:-mainnet}"
MONERO_WALLET_RPC_TRUSTED_DAEMON="${MONERO_WALLET_RPC_TRUSTED_DAEMON:-1}"

require_env MONERO_WALLET_DIR
require_env MONERO_DAEMON_ADDRESS
require_env MONERO_WALLET_RPC_PORT
require_env MONERO_WALLET_RPC_LOG

case "$MONERO_NETWORK" in
  mainnet)
    network_args=()
    ;;
  stagenet)
    network_args=(--stagenet)
    ;;
  testnet)
    network_args=(--testnet)
    ;;
  *)
    printf 'MONERO_NETWORK must be mainnet, stagenet, or testnet\n' >&2
    exit 2
    ;;
esac

trusted_args=()
case "$MONERO_WALLET_RPC_TRUSTED_DAEMON" in
  1 | true | TRUE | yes | YES)
    trusted_args=(--trusted-daemon)
    ;;
  0 | false | FALSE | no | NO)
    ;;
  *)
    printf 'MONERO_WALLET_RPC_TRUSTED_DAEMON must be boolean-like\n' >&2
    exit 2
    ;;
esac

install -d -m 0700 "$MONERO_WALLET_DIR"
install -d -m 0700 "$(dirname "$MONERO_WALLET_RPC_LOG")"

exec "$MONERO_WALLET_RPC_BIN" \
  "${network_args[@]}" \
  --wallet-dir "$MONERO_WALLET_DIR" \
  --daemon-address "$MONERO_DAEMON_ADDRESS" \
  "${trusted_args[@]}" \
  --rpc-bind-ip 127.0.0.1 \
  --rpc-bind-port "$MONERO_WALLET_RPC_PORT" \
  --disable-rpc-login \
  --log-file "$MONERO_WALLET_RPC_LOG" \
  --non-interactive
