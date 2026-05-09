#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-/opt/monero-starknet-atomic-swap}"
SCRIPT_DIR="${SCRIPT_DIR:-${REPO_ROOT}/ops/claim-relayer}"
RELAYER_CONFIG="${RELAYER_CONFIG:-/etc/atomic-swap/claim-relayer.config.json}"
RELAYER_ARTIFACT="${RELAYER_ARTIFACT:-${REPO_ROOT}/rust/target/release/claim_relayer_service}"
HANDOFF_PACKET="${HANDOFF_PACKET:-}"
RUN_HEALTHCHECK="${RUN_HEALTHCHECK:-1}"
RUN_RELAYER_DRY_RUN="${RUN_RELAYER_DRY_RUN:-1}"
DRILL_DIR="${DRILL_DIR:-}"

require() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'Missing required command: %s\n' "$1" >&2
    exit 1
  }
}

section() {
  printf '\n== %s ==\n' "$*"
}

require python3

if [ -z "$DRILL_DIR" ]; then
  DRILL_DIR="$(mktemp -d /tmp/claim-relayer-handoff-drill.XXXXXX)"
else
  mkdir -p "$DRILL_DIR"
fi
HANDOFF_PACKET="${HANDOFF_PACKET:-${DRILL_DIR}/claim-relayer-handoff.json}"

section "Generate handoff packet"
"${SCRIPT_DIR}/claim-relayer-handoff-packet.py" \
  --config "$RELAYER_CONFIG" \
  --repo-root "$REPO_ROOT" \
  --artifact "$RELAYER_ARTIFACT" \
  --output "$HANDOFF_PACKET"
python3 -m json.tool "$HANDOFF_PACKET" >/dev/null

section "Verify handoff packet"
"${SCRIPT_DIR}/verify-handoff-packet.py" \
  --require-artifact \
  "$HANDOFF_PACKET"

python3 - "$HANDOFF_PACKET" <<'PY'
import json
import sys

packet = json.load(open(sys.argv[1], encoding="utf-8"))
config = packet["config"]
print(f"packet={sys.argv[1]}")
print(f"warnings={len(packet.get('warnings') or [])}")
print(f"locks={len(config.get('locks') or [])}")
print(f"discoveries={len(config.get('discoveries') or [])}")
print(f"cursor_entries={len((config.get('cursor_dir') or {}).get('entries') or [])}")
PY

if [ "$RUN_HEALTHCHECK" = "1" ]; then
  section "Healthcheck rehearsal"
  healthcheck_env=(
    "RELAYER_EXPECT_ACTIVE=${RELAYER_EXPECT_ACTIVE:-0}"
    "WALLET_RPC_EXPECT_ACTIVE=${WALLET_RPC_EXPECT_ACTIVE:-0}"
    "RELAYER_MAX_CURSOR_AGE_SECS=${RELAYER_MAX_CURSOR_AGE_SECS:-86400}"
    "RELAYER_CONFIG=${RELAYER_CONFIG}"
    "RELAYER_CURSOR_DIR=${RELAYER_CURSOR_DIR:-/var/lib/atomic-swap/claim-relayer/cursors}"
  )
  if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
    sudo env "${healthcheck_env[@]}" "${SCRIPT_DIR}/claim-relayer-healthcheck.sh"
  else
    env "${healthcheck_env[@]}" "${SCRIPT_DIR}/claim-relayer-healthcheck.sh"
  fi
fi

if [ "$RUN_RELAYER_DRY_RUN" = "1" ]; then
  section "Relayer dry-run with temporary cursors"
  DRILL_CONFIG="${DRILL_DIR}/claim-relayer.config.json"
  DRILL_CURSOR_DIR="${DRILL_DIR}/cursors"
  mkdir -p "$DRILL_CURSOR_DIR"
  python3 - "$RELAYER_CONFIG" "$DRILL_CONFIG" "$DRILL_CURSOR_DIR" <<'PY'
import json
import sys

source, destination, cursor_dir = sys.argv[1:]
with open(source, encoding="utf-8") as handle:
    config = json.load(handle)
defaults = config.setdefault("defaults", {})
defaults["cursor_dir"] = cursor_dir
with open(destination, "w", encoding="utf-8") as handle:
    json.dump(config, handle, indent=2)
    handle.write("\n")
PY
  "$RELAYER_ARTIFACT" \
    --config "$DRILL_CONFIG" \
    --dry-run \
    --once
fi

section "Drill complete"
printf 'handoff_packet=%s\n' "$HANDOFF_PACKET"
