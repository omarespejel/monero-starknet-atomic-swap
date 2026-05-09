#!/usr/bin/env bash
set -euo pipefail

FAILED_UNIT="${1:-unknown-unit}"
RELAYER_ALERT_WEBHOOK_URL="${RELAYER_ALERT_WEBHOOK_URL:-}"
RELAYER_ALERT_ENVIRONMENT="${RELAYER_ALERT_ENVIRONMENT:-unknown}"
RELAYER_SERVICE="${RELAYER_SERVICE:-monero-claim-relayer.service}"
WALLET_RPC_SERVICE="${WALLET_RPC_SERVICE:-monero-claim-wallet-rpc.service}"

if [ -z "$RELAYER_ALERT_WEBHOOK_URL" ]; then
  printf 'RELAYER_ALERT_WEBHOOK_URL is unset; alert for %s not sent\n' "$FAILED_UNIT" >&2
  exit 0
fi

host="$(hostname -f 2>/dev/null || hostname)"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
relayer_state="$(systemctl show "$RELAYER_SERVICE" -p ActiveState -p SubState -p Result --value 2>/dev/null | paste -sd '/' - || true)"
wallet_state="$(systemctl show "$WALLET_RPC_SERVICE" -p ActiveState -p SubState -p Result --value 2>/dev/null | paste -sd '/' - || true)"

payload="$(
  python3 - "$FAILED_UNIT" "$RELAYER_ALERT_ENVIRONMENT" "$host" "$timestamp" "$relayer_state" "$wallet_state" <<'PY'
import json
import sys

failed_unit, environment, host, timestamp, relayer_state, wallet_state = sys.argv[1:]
text = (
    f"Atomic swap relayer healthcheck failed: {failed_unit}\n"
    f"environment={environment} host={host} timestamp={timestamp}\n"
    f"relayer={relayer_state or 'unknown'} wallet_rpc={wallet_state or 'unknown'}"
)
print(json.dumps({"text": text}))
PY
)"

curl -fsS --max-time 10 \
  -H 'Content-Type: application/json' \
  --data-binary "$payload" \
  "$RELAYER_ALERT_WEBHOOK_URL" >/dev/null

printf 'Sent relayer alert for %s\n' "$FAILED_UNIT"
