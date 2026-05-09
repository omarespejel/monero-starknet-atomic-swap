#!/usr/bin/env bash
set -euo pipefail

FAILED_UNIT="${1:-unknown-unit}"
RELAYER_ALERT_WEBHOOK_URL="${RELAYER_ALERT_WEBHOOK_URL:-}"
RELAYER_ALERT_FILE="${RELAYER_ALERT_FILE:-}"
RELAYER_ALERT_ENVIRONMENT="${RELAYER_ALERT_ENVIRONMENT:-unknown}"
RELAYER_ALERT_FORMAT="${RELAYER_ALERT_FORMAT:-slack}"
RELAYER_ALERT_LEVEL="${RELAYER_ALERT_LEVEL:-ERROR}"
RELAYER_ALERT_PRIORITY="${RELAYER_ALERT_PRIORITY:-HIGH}"
RELAYER_ALERT_SERVICE="${RELAYER_ALERT_SERVICE:-monero-starknet-atomic-swap-relayer}"
RELAYER_ALERT_SUMMARY_PREFIX="${RELAYER_ALERT_SUMMARY_PREFIX:-Atomic swap relayer healthcheck failed}"
RELAYER_ALERT_SOURCE_TAG="${RELAYER_ALERT_SOURCE_TAG:-monero-claim-relayer-healthcheck}"
RELAYER_ALERT_COMPONENT="${RELAYER_ALERT_COMPONENT:-claim-relayer}"
RELAYER_SERVICE="${RELAYER_SERVICE:-monero-claim-relayer.service}"
WALLET_RPC_SERVICE="${WALLET_RPC_SERVICE:-monero-claim-wallet-rpc.service}"

if [ -z "$RELAYER_ALERT_WEBHOOK_URL" ] && [ -z "$RELAYER_ALERT_FILE" ]; then
  printf 'RELAYER_ALERT_WEBHOOK_URL and RELAYER_ALERT_FILE are unset; alert for %s not sent\n' "$FAILED_UNIT" >&2
  exit 0
fi

host="$(hostname -f 2>/dev/null || hostname)"
timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
relayer_state="$(systemctl show "$RELAYER_SERVICE" -p ActiveState -p SubState -p Result --value 2>/dev/null | paste -sd '/' - || true)"
wallet_state="$(systemctl show "$WALLET_RPC_SERVICE" -p ActiveState -p SubState -p Result --value 2>/dev/null | paste -sd '/' - || true)"

payload="$(
  python3 - \
    "$FAILED_UNIT" \
    "$RELAYER_ALERT_ENVIRONMENT" \
    "$host" \
    "$timestamp" \
    "$relayer_state" \
    "$wallet_state" \
    "$RELAYER_ALERT_FORMAT" \
    "$RELAYER_ALERT_LEVEL" \
    "$RELAYER_ALERT_PRIORITY" \
    "$RELAYER_ALERT_SERVICE" \
    "$RELAYER_ALERT_SUMMARY_PREFIX" \
    "$RELAYER_ALERT_SOURCE_TAG" \
    "$RELAYER_ALERT_COMPONENT" <<'PY'
import json
import sys

(
    failed_unit,
    environment,
    host,
    timestamp,
    relayer_state,
    wallet_state,
    alert_format,
    alert_level,
    alert_priority,
    service,
    summary_prefix,
    source_tag,
    component,
) = sys.argv[1:]
summary = f"{summary_prefix}: {failed_unit}"
text = (
    f"{summary}\n"
    f"environment={environment} host={host} timestamp={timestamp}\n"
    f"relayer={relayer_state or 'unknown'} wallet_rpc={wallet_state or 'unknown'}"
)
if alert_format == "firehydrant":
    payload = {
        "summary": summary,
        "body": text,
        "level": alert_level,
        "status": "OPEN",
        "idempotency_key": f"atomic-swap-relayer:{environment}:{failed_unit}",
        "tags": [
            f"service:{service}",
            f"environment:{environment}",
            f"host:{host}",
            f"source:{source_tag}",
            f"component:{component}",
        ],
        "annotations": {
            "signals.firehydrant.com/notification-priority": alert_priority,
            "failed_unit": failed_unit,
            "component": component,
            "relayer_state": relayer_state or "unknown",
            "wallet_rpc_state": wallet_state or "unknown",
            "timestamp": timestamp,
        },
    }
else:
    payload = {"text": text}
print(json.dumps(payload))
PY
)"

if [ -n "$RELAYER_ALERT_FILE" ]; then
  umask 077
  printf '%s\n' "$payload" >> "$RELAYER_ALERT_FILE"
  printf 'Wrote relayer alert for %s to %s\n' "$FAILED_UNIT" "$RELAYER_ALERT_FILE"
fi

if [ -n "$RELAYER_ALERT_WEBHOOK_URL" ]; then
  curl -fsS --max-time 10 \
    -H 'Content-Type: application/json' \
    --data-binary "$payload" \
    "$RELAYER_ALERT_WEBHOOK_URL" >/dev/null

  printf 'Sent relayer alert for %s\n' "$FAILED_UNIT"
fi
