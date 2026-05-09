#!/usr/bin/env bash
set -euo pipefail

RELAYER_CONFIG="${RELAYER_CONFIG:-/etc/atomic-swap/claim-relayer.config.json}"
RELAYER_CURSOR_DIR="${RELAYER_CURSOR_DIR:-/var/lib/atomic-swap/claim-relayer/cursors}"
RELAYER_SERVICE="${RELAYER_SERVICE:-monero-claim-relayer.service}"
WALLET_RPC_SERVICE="${WALLET_RPC_SERVICE:-monero-claim-wallet-rpc.service}"
WALLET_RPC_URL="${WALLET_RPC_URL:-http://127.0.0.1:38091/json_rpc}"
RELAYER_EXPECT_ACTIVE="${RELAYER_EXPECT_ACTIVE:-1}"
WALLET_RPC_EXPECT_ACTIVE="${WALLET_RPC_EXPECT_ACTIVE:-1}"
RELAYER_MAX_CURSOR_AGE_SECS="${RELAYER_MAX_CURSOR_AGE_SECS:-600}"
RELAYER_JOURNAL_SINCE="${RELAYER_JOURNAL_SINCE:-15 minutes ago}"

failures=0

fail() {
  printf 'FAIL %s\n' "$*" >&2
  failures=$((failures + 1))
}

ok() {
  printf 'OK %s\n' "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

require_cmd python3
require_cmd systemctl
require_cmd journalctl
require_cmd curl

if [ ! -r "$RELAYER_CONFIG" ]; then
  fail "relayer config is not readable: $RELAYER_CONFIG"
else
  config_summary="$(
    python3 - "$RELAYER_CONFIG" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as handle:
    config = json.load(handle)

locks = [lock for lock in config.get("locks", []) if lock.get("enabled", True)]
discoveries = [
    discovery
    for discovery in config.get("discoveries", [])
    if discovery.get("enabled", True)
]
for discovery in discoveries:
    if not str(discovery.get("registry_address", "")).strip():
        raise SystemExit(f"enabled discovery {discovery.get('id', '<missing>')} missing registry_address")
    if not discovery.get("start_block"):
        raise SystemExit(f"enabled discovery {discovery.get('id', '<missing>')} missing nonzero start_block")
print(f"enabled_locks={len(locks)} enabled_discoveries={len(discoveries)}")
if not locks and not discoveries:
    raise SystemExit("no enabled locks or registry discoveries")
PY
  )" || fail "relayer config validation failed"
  if [ -n "${config_summary:-}" ]; then
    ok "config $config_summary"
  fi
fi

if [ "$RELAYER_EXPECT_ACTIVE" = "1" ]; then
  if systemctl is-active --quiet "$RELAYER_SERVICE"; then
    ok "$RELAYER_SERVICE active"
  else
    fail "$RELAYER_SERVICE is not active"
  fi
else
  ok "$RELAYER_SERVICE active check disabled"
fi

if [ "$WALLET_RPC_EXPECT_ACTIVE" = "1" ]; then
  if systemctl is-active --quiet "$WALLET_RPC_SERVICE"; then
    ok "$WALLET_RPC_SERVICE active"
  else
    fail "$WALLET_RPC_SERVICE is not active"
  fi

  wallet_payload='{"jsonrpc":"2.0","id":"0","method":"get_version"}'
  if curl -fsS --max-time 8 "$WALLET_RPC_URL" \
    -H 'Content-Type: application/json' \
    --data-binary "$wallet_payload" >/dev/null; then
    ok "wallet-rpc responds"
  else
    fail "wallet-rpc health request failed at $WALLET_RPC_URL"
  fi
else
  ok "$WALLET_RPC_SERVICE active check disabled"
fi

if [ ! -d "$RELAYER_CURSOR_DIR" ]; then
  fail "cursor directory missing: $RELAYER_CURSOR_DIR"
else
  cursor_count="$(find "$RELAYER_CURSOR_DIR" -maxdepth 1 -type f -name '*.json' | wc -l | tr -d ' ')"
  if [ "$cursor_count" = "0" ]; then
    fail "no relayer cursor files in $RELAYER_CURSOR_DIR"
  else
    ok "cursor_count=$cursor_count"
    newest_cursor_epoch="$(
      find "$RELAYER_CURSOR_DIR" -maxdepth 1 -type f -name '*.json' -printf '%T@\n' \
        | sort -nr \
        | head -1 \
        | cut -d. -f1
    )"
    now_epoch="$(date +%s)"
    cursor_age=$((now_epoch - newest_cursor_epoch))
    if [ "$cursor_age" -le "$RELAYER_MAX_CURSOR_AGE_SECS" ]; then
      ok "newest_cursor_age_secs=$cursor_age"
    else
      fail "newest cursor is stale: age ${cursor_age}s > ${RELAYER_MAX_CURSOR_AGE_SECS}s"
    fi
  fi
fi

journal_output="$(
  journalctl -u "$RELAYER_SERVICE" --since "$RELAYER_JOURNAL_SINCE" --no-pager 2>/dev/null || true
)"
if printf '%s\n' "$journal_output" | grep -E \
  'failed to load claim relayer config|claim relayer lock pass failed|Failed to read registry events|Failed to read latest block for discovery' >/dev/null; then
  fail "recent relayer journal contains failure patterns since $RELAYER_JOURNAL_SINCE"
else
  ok "recent relayer journal clean since $RELAYER_JOURNAL_SINCE"
fi

if [ "$failures" -gt 0 ]; then
  printf 'claim relayer healthcheck failed: %s issue(s)\n' "$failures" >&2
  exit 1
fi

ok "claim relayer healthcheck passed"
