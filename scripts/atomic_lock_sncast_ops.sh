#!/usr/bin/env bash
set -euo pipefail

NETWORK="${STARKNET_NETWORK:-sepolia}"
RPC_URL="${STARKNET_RPC_URL:-https://api.zan.top/public/starknet-sepolia/rpc/v0_10}"
SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-stealth-deployer-2026-01-21}"
SNCAST_ACCOUNTS_FILE="${SNCAST_ACCOUNTS_FILE:-$HOME/.starknet_accounts/starknet_open_zeppelin_accounts.json}"
TOKEN="${ATOMIC_SWAP_TOKEN_ADDRESS:-}"

usage() {
  cat <<'EOF'
Usage:
  scripts/atomic_lock_sncast_ops.sh state <contract>
  scripts/atomic_lock_sncast_ops.sh claim <contract>
  scripts/atomic_lock_sncast_ops.sh refund <contract>

Environment:
  STARKNET_RPC_URL
  SNCAST_ACCOUNT
  SNCAST_ACCOUNTS_FILE
  ATOMIC_SWAP_TOKEN_ADDRESS   optional, used for balance_of(contract)
EOF
}

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

redact_url() {
  python3 - "$1" <<'PY'
import re
import sys
from urllib.parse import urlsplit, urlunsplit

value = sys.argv[1]
if "://" not in value:
    print(value)
    raise SystemExit
parts = urlsplit(value)
netloc = parts.hostname or ""
if parts.port:
    netloc = f"{netloc}:{parts.port}"
if parts.username:
    netloc = f"{parts.username}:<redacted>@{netloc}"
path_parts = parts.path.split("/")
if path_parts and len(path_parts[-1]) >= 20 and re.fullmatch(r"[A-Za-z0-9_-]+", path_parts[-1]):
    path_parts[-1] = "<redacted>"
query = "<redacted>" if parts.query else ""
print(urlunsplit((parts.scheme, netloc, "/".join(path_parts), query, "")))
PY
}

if [ "$NETWORK" != "sepolia" ] && [ "$NETWORK" != "mainnet" ]; then
  echo "STARKNET_NETWORK must be sepolia or mainnet" >&2
  exit 1
fi
if [ "$NETWORK" = "mainnet" ]; then
  echo "Refusing mainnet operations from this helper. Use an audited release process." >&2
  exit 1
fi

ACTION="${1:-}"
CONTRACT="${2:-${ATOMIC_SWAP_CONTRACT_ADDRESS:-}}"

case "$ACTION" in
  state|claim|refund) ;;
  *) usage; exit 2 ;;
esac

if [ -z "$CONTRACT" ]; then
  echo "Missing contract address." >&2
  usage >&2
  exit 2
fi

require sncast
require python3

sncast_base() {
  sncast --json --accounts-file "$SNCAST_ACCOUNTS_FILE" --account "$SNCAST_ACCOUNT" "$@"
}

call_lock() {
  local function_name="$1"
  sncast_base call --url "$RPC_URL" --block-id latest \
    --contract-address "$CONTRACT" --function "$function_name"
}

print_state() {
  echo "=== AtomicLock state ==="
  echo "network=$NETWORK"
  echo "rpc=$(redact_url "$RPC_URL")"
  echo "account=$SNCAST_ACCOUNT"
  echo "contract=$CONTRACT"
  echo
  echo "is_secret_revealed:"
  call_lock is_secret_revealed
  echo
  echo "is_unlocked:"
  call_lock is_unlocked
  echo
  echo "get_claimable_after:"
  call_lock get_claimable_after
  echo
  echo "get_lock_until:"
  call_lock get_lock_until

  if [ -n "$TOKEN" ] && [ "$TOKEN" != "0x0" ]; then
    echo
    echo "token balance_of(contract):"
    sncast_base call --url "$RPC_URL" --block-id latest \
      --contract-address "$TOKEN" --function balance_of \
      --calldata "$CONTRACT"
  fi
}

case "$ACTION" in
  state)
    print_state
    ;;
  claim)
    sncast_base --wait invoke --url "$RPC_URL" \
      --contract-address "$CONTRACT" --function claim_tokens
    echo
    print_state
    ;;
  refund)
    sncast_base --wait invoke --url "$RPC_URL" \
      --contract-address "$CONTRACT" --function refund
    echo
    print_state
    ;;
esac
