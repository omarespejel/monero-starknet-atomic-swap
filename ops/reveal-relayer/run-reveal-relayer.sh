#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"
  if [ -z "${!name:-}" ]; then
    printf 'Missing required environment variable: %s\n' "$name" >&2
    exit 2
  fi
}

check_integer_env() {
  local name="$1"
  local value="${!name:-}"
  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s must be a non-negative integer\n' "$name" >&2
    exit 2
  fi
}

check_secret_file() {
  local path="$1"
  if [ ! -f "$path" ]; then
    printf 'REVEAL_SECRET_FILE does not exist: %s\n' "$path" >&2
    exit 2
  fi

  local mode=""
  if mode="$(stat -c '%a' "$path" 2>/dev/null)"; then
    local group_perm="${mode: -2:1}"
    local other_perm="${mode: -1}"
    if [ "$group_perm" != "0" ] || [ "$other_perm" != "0" ]; then
      printf 'REVEAL_SECRET_FILE must not be group/world accessible: %s\n' "$path" >&2
      exit 2
    fi
  fi
}

REVEAL_RELAYER_BIN="${REVEAL_RELAYER_BIN:-/opt/monero-starknet-atomic-swap/rust/target/release/relay_reveal}"
ATOMIC_LOCK_OPS_SCRIPT="${ATOMIC_LOCK_OPS_SCRIPT:-/opt/monero-starknet-atomic-swap/scripts/atomic_lock_sncast_ops.sh}"
STARKNET_NETWORK="${STARKNET_NETWORK:-sepolia}"
MONERO_WALLET_RPC_URL="${MONERO_WALLET_RPC_URL:-http://127.0.0.1:38090/json_rpc}"
MONERO_CONFIRMATIONS="${MONERO_CONFIRMATIONS:-10}"
MONERO_POLL_INTERVAL_SECS="${MONERO_POLL_INTERVAL_SECS:-20}"
MONERO_REVEAL_TIMEOUT_SECS="${MONERO_REVEAL_TIMEOUT_SECS:-0}"
REVEAL_DRY_RUN="${REVEAL_DRY_RUN:-0}"
REVEAL_CLAIM_AFTER_REVEAL="${REVEAL_CLAIM_AFTER_REVEAL:-0}"
REVEAL_CLAIM_GRACE_SECS="${REVEAL_CLAIM_GRACE_SECS:-7200}"
REVEAL_CLAIM_RETRY_INTERVAL_SECS="${REVEAL_CLAIM_RETRY_INTERVAL_SECS:-30}"
REVEAL_CLAIM_TIMEOUT_SECS="${REVEAL_CLAIM_TIMEOUT_SECS:-1800}"

require_env STARKNET_RPC_URL
require_env SNCAST_ACCOUNT
require_env ATOMIC_SWAP_CONTRACT_ADDRESS
require_env EXPECTED_MONERO_AMOUNT_PICONERO
require_env REVEAL_SECRET_FILE

check_integer_env EXPECTED_MONERO_AMOUNT_PICONERO
check_integer_env MONERO_CONFIRMATIONS
check_integer_env MONERO_POLL_INTERVAL_SECS
check_integer_env MONERO_REVEAL_TIMEOUT_SECS
check_integer_env REVEAL_CLAIM_GRACE_SECS
check_integer_env REVEAL_CLAIM_RETRY_INTERVAL_SECS
check_integer_env REVEAL_CLAIM_TIMEOUT_SECS
check_secret_file "$REVEAL_SECRET_FILE"

if [ "$REVEAL_DRY_RUN" != "0" ] && [ "$REVEAL_DRY_RUN" != "1" ]; then
  printf 'REVEAL_DRY_RUN must be 0 or 1\n' >&2
  exit 2
fi
if [ "$REVEAL_CLAIM_AFTER_REVEAL" != "0" ] && [ "$REVEAL_CLAIM_AFTER_REVEAL" != "1" ]; then
  printf 'REVEAL_CLAIM_AFTER_REVEAL must be 0 or 1\n' >&2
  exit 2
fi

args=(
  --starknet-rpc "$STARKNET_RPC_URL"
  --starknet-network "$STARKNET_NETWORK"
  --sncast-account "$SNCAST_ACCOUNT"
  --contract-address "$ATOMIC_SWAP_CONTRACT_ADDRESS"
  --atomic-lock-ops-script "$ATOMIC_LOCK_OPS_SCRIPT"
  --secret-file "$REVEAL_SECRET_FILE"
  --wallet-rpc-url "$MONERO_WALLET_RPC_URL"
  --expected-monero-amount-piconero "$EXPECTED_MONERO_AMOUNT_PICONERO"
  --confirmations "$MONERO_CONFIRMATIONS"
  --poll-interval-secs "$MONERO_POLL_INTERVAL_SECS"
  --timeout-secs "$MONERO_REVEAL_TIMEOUT_SECS"
  --claim-grace-secs "$REVEAL_CLAIM_GRACE_SECS"
  --claim-retry-interval-secs "$REVEAL_CLAIM_RETRY_INTERVAL_SECS"
  --claim-timeout-secs "$REVEAL_CLAIM_TIMEOUT_SECS"
)

if [ -n "${SNCAST_ACCOUNTS_FILE:-}" ]; then
  args+=(--sncast-accounts-file "$SNCAST_ACCOUNTS_FILE")
fi
if [ -n "${ATOMIC_SWAP_TOKEN_ADDRESS:-}" ]; then
  args+=(--token-address "$ATOMIC_SWAP_TOKEN_ADDRESS")
fi
if [ -n "${MONERO_TXID:-}" ]; then
  args+=(--monero-txid "$MONERO_TXID")
fi
if [ "$REVEAL_DRY_RUN" = "1" ]; then
  args+=(--dry-run)
fi
if [ "$REVEAL_CLAIM_AFTER_REVEAL" = "1" ]; then
  args+=(--claim-after-reveal)
fi

printf 'Starting reveal relayer for contract=%s monero_txid=%s expected_piconero=%s confirmations=%s dry_run=%s claim_after_reveal=%s\n' \
  "$ATOMIC_SWAP_CONTRACT_ADDRESS" \
  "${MONERO_TXID:-<scan-wallet>}" \
  "$EXPECTED_MONERO_AMOUNT_PICONERO" \
  "$MONERO_CONFIRMATIONS" \
  "$REVEAL_DRY_RUN" \
  "$REVEAL_CLAIM_AFTER_REVEAL"

exec "$REVEAL_RELAYER_BIN" "${args[@]}"
