#!/usr/bin/env bash
set -euo pipefail

VM_NAME="${MONERO_VM_NAME:-monero-stagenet}"
PORT="${MONERO_WALLET_RPC_PORT:-38090}"
PIDFILE="${TMPDIR:-/tmp}/${VM_NAME}-wallet-rpc-tunnel.pid"
SSH_CONFIG="${HOME}/.lima/${VM_NAME}/ssh.config"
SSH_HOST="lima-${VM_NAME}"

usage() {
  printf 'Usage: %s {start|stop|status|smoke|vm-smoke|vm-address|vm-balance|vm-height}\n' "$0"
}

listen_pid() {
  lsof -tiTCP:"${PORT}" -sTCP:LISTEN 2>/dev/null || true
}

start_tunnel() {
  if [ ! -f "${SSH_CONFIG}" ]; then
    printf 'Missing Lima SSH config: %s\n' "${SSH_CONFIG}" >&2
    exit 1
  fi

  existing_pid="$(listen_pid)"
  if [ -n "${existing_pid}" ]; then
    printf 'Tunnel already listening on 127.0.0.1:%s (pid %s)\n' "${PORT}" "${existing_pid}"
    exit 0
  fi

  ssh -F "${SSH_CONFIG}" -N -L "127.0.0.1:${PORT}:127.0.0.1:${PORT}" "${SSH_HOST}" &
  tunnel_pid="$!"
  printf '%s\n' "${tunnel_pid}" > "${PIDFILE}"
  printf 'Started tunnel on 127.0.0.1:%s (pid %s)\n' "${PORT}" "${tunnel_pid}"
}

stop_tunnel() {
  if [ -f "${PIDFILE}" ]; then
    tunnel_pid="$(cat "${PIDFILE}")"
    kill "${tunnel_pid}" 2>/dev/null || true
    rm -f "${PIDFILE}"
  fi

  existing_pid="$(listen_pid)"
  if [ -n "${existing_pid}" ]; then
    kill ${existing_pid} 2>/dev/null || true
  fi

  printf 'Stopped tunnel on 127.0.0.1:%s\n' "${PORT}"
}

status_tunnel() {
  limactl list "${VM_NAME}"
  printf '\nHost listener:\n'
  lsof -nP -iTCP:"${PORT}" -sTCP:LISTEN || true
  printf '\nVM Monero processes:\n'
  limactl shell "${VM_NAME}" -- sh -lc \
    "ps -eo pid,args | awk '/monero-wallet-rpc|monerod/ && !/awk/ { print }'"
}

smoke_tunnel() {
  curl -s --max-time 5 "http://127.0.0.1:${PORT}/json_rpc" \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","id":"0","method":"get_balance"}'
  printf '\n'
}

vm_rpc() {
  local method="$1"

  case "${method}" in
    get_address|get_balance|get_height) ;;
    *)
      printf 'Unsupported wallet RPC method: %s\n' "${method}" >&2
      exit 2
      ;;
  esac

  local payload
  payload="$(python3 - "${method}" <<'PY'
import json
import sys

print(json.dumps({"jsonrpc": "2.0", "id": "0", "method": sys.argv[1]}))
PY
)"

  limactl shell "${VM_NAME}" -- sh -lc \
    "curl -s --max-time 8 'http://127.0.0.1:${PORT}/json_rpc' -H 'Content-Type: application/json' --data-binary '${payload}'"
  printf '\n'
}

case "${1:-}" in
  start) start_tunnel ;;
  stop) stop_tunnel ;;
  status) status_tunnel ;;
  smoke) smoke_tunnel ;;
  vm-smoke|vm-balance) vm_rpc get_balance ;;
  vm-address) vm_rpc get_address ;;
  vm-height) vm_rpc get_height ;;
  *) usage; exit 2 ;;
esac
