#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NETWORK="${STARKNET_NETWORK:-sepolia}"
RPC_URL="${STARKNET_RPC_URL:-https://api.zan.top/public/starknet-sepolia/rpc/v0_10}"
SNCAST_ACCOUNT="${SNCAST_ACCOUNT:-stealth-deployer-2026-01-21}"
SNCAST_ACCOUNTS_FILE="${SNCAST_ACCOUNTS_FILE:-$HOME/.starknet_accounts/starknet_open_zeppelin_accounts.json}"
CLASS_HASH_OVERRIDE="${ATOMIC_SWAP_CLASS_HASH:-}"

TOKEN="${ATOMIC_SWAP_TOKEN_ADDRESS:-0x0}"
AMOUNT="${ATOMIC_SWAP_AMOUNT:-0}"
DEPOSITOR="${ATOMIC_SWAP_DEPOSITOR:-${STARKNET_ACCOUNT_ADDRESS:-}}"
LOCK_UNTIL="${ATOMIC_SWAP_LOCK_UNTIL:-}"
SECRET_HEX="${ATOMIC_SWAP_SECRET_HEX:-1212121212121212121212121212121212121212121212121212121212121212}"

PUBLIC_CANONICAL_TEST_SECRET="1212121212121212121212121212121212121212121212121212121212121212"

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

tmpfile() {
  mktemp "${TMPDIR:-/tmp}/$1.XXXXXX"
}

parse_json_field() {
  local file="$1"
  local command="$2"
  local field="$3"
  python3 - "$file" "$command" "$field" <<'PY'
import json
import sys

path, command, field = sys.argv[1:]
value = ""
with open(path, "r", encoding="utf-8") as handle:
    for line in handle:
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if obj.get("command") == command and field in obj:
            value = obj[field]
if not value:
    raise SystemExit(f"missing {field} in {path}")
print(value)
PY
}

u256_parts() {
  python3 - "$1" <<'PY'
import sys
value = int(sys.argv[1], 0)
mask = (1 << 128) - 1
print(hex(value & mask), hex(value >> 128))
PY
}

secret_bytearray_calldata() {
  python3 - "$1" <<'PY'
import sys
secret = sys.argv[1].removeprefix("0x").lower()
if len(secret) != 64 or any(c not in "0123456789abcdef" for c in secret):
    raise SystemExit("ATOMIC_SWAP_SECRET_HEX must be exactly 32 bytes / 64 hex chars")
print("0x1", "0x" + secret[:62], "0x" + secret[62:], "0x1")
PY
}

if [ "$NETWORK" != "sepolia" ] && [ "$NETWORK" != "mainnet" ]; then
  echo "STARKNET_NETWORK must be sepolia or mainnet" >&2
  exit 1
fi
if [ "$NETWORK" = "mainnet" ]; then
  echo "Refusing mainnet deployment from this helper. Use an audited release process." >&2
  exit 1
fi

if [ "$AMOUNT" != "0" ] && [ "$TOKEN" != "0x0" ]; then
  if [ -z "$DEPOSITOR" ]; then
    echo "Set ATOMIC_SWAP_DEPOSITOR or STARKNET_ACCOUNT_ADDRESS for non-zero token locks." >&2
    exit 1
  fi
  if [ "${SECRET_HEX#0x}" = "$PUBLIC_CANONICAL_TEST_SECRET" ] && [ "${ATOMIC_SWAP_CONFIRM_PUBLIC_TEST_SECRET:-0}" != "1" ]; then
    echo "This uses the public canonical test secret. Set ATOMIC_SWAP_CONFIRM_PUBLIC_TEST_SECRET=1 only for a tiny test amount, or provide ATOMIC_SWAP_SECRET_HEX." >&2
    exit 1
  fi
fi

require scarb
require sncast
require python3

RPC_URL_REDACTED="$(redact_url "$RPC_URL")"

echo "=== AtomicLock Sepolia Rehearsal (sncast) ==="
echo "RPC: $RPC_URL_REDACTED"
echo "Account: $SNCAST_ACCOUNT"
echo "Accounts file: $SNCAST_ACCOUNTS_FILE"
echo "Class hash override: ${CLASS_HASH_OVERRIDE:-none}"
echo "Token: $TOKEN"
echo "Amount: $AMOUNT"
echo "Depositor: ${DEPOSITOR:-0x0}"
echo "Lock until: ${LOCK_UNTIL:-default}"

cd "$ROOT_DIR/cairo"

DEPLOY_LOG="$(tmpfile atomic-sncast-deploy)"

if [ -n "$CLASS_HASH_OVERRIDE" ]; then
  CLASS_HASH="$CLASS_HASH_OVERRIDE"
  DECLARE_TX=""
else
  scarb build
  DECLARE_LOG="$(tmpfile atomic-sncast-declare)"
  sncast --json --accounts-file "$SNCAST_ACCOUNTS_FILE" --account "$SNCAST_ACCOUNT" --wait \
    declare --url "$RPC_URL" --contract-name AtomicLock | tee "$DECLARE_LOG"

  CLASS_HASH="$(parse_json_field "$DECLARE_LOG" declare class_hash)"
  DECLARE_TX="$(parse_json_field "$DECLARE_LOG" declare transaction_hash)"
fi

cd "$ROOT_DIR"
CALldata_PATH="$(tmpfile atomic-constructor-calldata)"
if [ -n "$LOCK_UNTIL" ]; then
  python3 tools/generate_deploy_calldata.py \
    --network "$NETWORK" \
    --lock-until "$LOCK_UNTIL" \
    --depositor "${DEPOSITOR:-0x0}" \
    --token "$TOKEN" \
    --amount "$AMOUNT" > "$CALldata_PATH"
else
  python3 tools/generate_deploy_calldata.py \
    --network "$NETWORK" \
    --depositor "${DEPOSITOR:-0x0}" \
    --token "$TOKEN" \
    --amount "$AMOUNT" > "$CALldata_PATH"
fi

cd "$ROOT_DIR/cairo"
sncast --json --accounts-file "$SNCAST_ACCOUNTS_FILE" --account "$SNCAST_ACCOUNT" --wait \
  deploy --url "$RPC_URL" --class-hash "$CLASS_HASH" --constructor-calldata $(cat "$CALldata_PATH") | tee "$DEPLOY_LOG"

CONTRACT_ADDRESS="$(parse_json_field "$DEPLOY_LOG" deploy contract_address)"
DEPLOY_TX="$(parse_json_field "$DEPLOY_LOG" deploy transaction_hash)"

APPROVE_TX=""
DEPOSIT_TX=""
REVEAL_TX=""
CLAIMABLE_AFTER=""

if [ "${ATOMIC_SWAP_DEPOSIT:-0}" = "1" ]; then
  read -r AMOUNT_LOW AMOUNT_HIGH <<< "$(u256_parts "$AMOUNT")"
  APPROVE_LOG="$(tmpfile atomic-sncast-approve)"
  DEPOSIT_LOG="$(tmpfile atomic-sncast-deposit)"

  sncast --json --accounts-file "$SNCAST_ACCOUNTS_FILE" --account "$SNCAST_ACCOUNT" --wait \
    invoke --url "$RPC_URL" --contract-address "$TOKEN" --function approve \
    --calldata "$CONTRACT_ADDRESS" "$AMOUNT_LOW" "$AMOUNT_HIGH" | tee "$APPROVE_LOG"
  APPROVE_TX="$(parse_json_field "$APPROVE_LOG" invoke transaction_hash)"

  sncast --json --accounts-file "$SNCAST_ACCOUNTS_FILE" --account "$SNCAST_ACCOUNT" --wait \
    invoke --url "$RPC_URL" --contract-address "$CONTRACT_ADDRESS" --function deposit | tee "$DEPOSIT_LOG"
  DEPOSIT_TX="$(parse_json_field "$DEPOSIT_LOG" invoke transaction_hash)"
fi

if [ "${ATOMIC_SWAP_REVEAL:-0}" = "1" ]; then
  read -r -a SECRET_CALLDATA <<< "$(secret_bytearray_calldata "$SECRET_HEX")"
  REVEAL_LOG="$(tmpfile atomic-sncast-reveal)"
  sncast --json --accounts-file "$SNCAST_ACCOUNTS_FILE" --account "$SNCAST_ACCOUNT" --wait \
    invoke --url "$RPC_URL" --contract-address "$CONTRACT_ADDRESS" --function reveal_secret \
    --calldata "${SECRET_CALLDATA[@]}" | tee "$REVEAL_LOG"
  REVEAL_TX="$(parse_json_field "$REVEAL_LOG" invoke transaction_hash)"

  CLAIMABLE_AFTER="$(
    sncast --json --accounts-file "$SNCAST_ACCOUNTS_FILE" --account "$SNCAST_ACCOUNT" \
      call --url "$RPC_URL" --block-id latest --contract-address "$CONTRACT_ADDRESS" --function get_claimable_after \
      | python3 -c 'import json,sys; print(json.load(sys.stdin)["response_raw"][0])'
  )"
fi

cd "$ROOT_DIR"
mkdir -p "deployments/$NETWORK"
CLASS_HASH="$CLASS_HASH" DECLARE_TX="$DECLARE_TX" CONTRACT_ADDRESS="$CONTRACT_ADDRESS" DEPLOY_TX="$DEPLOY_TX" \
APPROVE_TX="$APPROVE_TX" DEPOSIT_TX="$DEPOSIT_TX" REVEAL_TX="$REVEAL_TX" CLAIMABLE_AFTER="$CLAIMABLE_AFTER" \
RPC_URL="$RPC_URL_REDACTED" SNCAST_ACCOUNT="$SNCAST_ACCOUNT" TOKEN="$TOKEN" AMOUNT="$AMOUNT" DEPOSITOR="${DEPOSITOR:-0x0}" \
LOCK_UNTIL="$LOCK_UNTIL" \
python3 - <<'PY'
import json
import os
from datetime import datetime, timezone
from pathlib import Path

record = {
    "timestamp": datetime.now(timezone.utc).isoformat(),
    "network": "sepolia",
    "rpc_url": os.environ["RPC_URL"],
    "account": os.environ["SNCAST_ACCOUNT"],
    "class_hash": os.environ["CLASS_HASH"],
    "declare_tx": os.environ["DECLARE_TX"],
    "contract_address": os.environ["CONTRACT_ADDRESS"],
    "deploy_tx": os.environ["DEPLOY_TX"],
    "depositor": os.environ["DEPOSITOR"],
    "token": os.environ["TOKEN"],
    "amount": os.environ["AMOUNT"],
}
if os.environ.get("LOCK_UNTIL"):
    record["lock_until"] = os.environ["LOCK_UNTIL"]
for env_name, key in [
    ("APPROVE_TX", "approve_tx"),
    ("DEPOSIT_TX", "deposit_tx"),
    ("REVEAL_TX", "reveal_tx"),
    ("CLAIMABLE_AFTER", "claimable_after"),
]:
    if os.environ.get(env_name):
        record[key] = os.environ[env_name]

path = Path("deployments/sepolia/sncast_latest.json")
path.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
print(f"Wrote {path}")
PY

echo "Contract: $CONTRACT_ADDRESS"
echo "Class hash: $CLASS_HASH"
