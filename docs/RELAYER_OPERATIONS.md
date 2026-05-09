# Claim Relayer Operations

This runbook is for the claim-side relayer that watches Starknet
`SecretRevealed` events and sweeps matching Monero outputs through
`monero-wallet-rpc`.

Do not run Monero daemons, wallet-rpc, or generated claim wallets on macOS.
Run this flow inside the Lima Monero VM or another dedicated Linux host.

## Binaries

- `claim_revealed_secrets`: one AtomicLock contract, useful for rehearsals and
  emergency one-off retries.
- `claim_relayer_service`: long-running multi-lock service. It reloads a JSON
  inventory, runs each enabled lock with an independent cursor, and keeps later
  locks moving if one lock hits an RPC error.
- `derive_claim_address`: stagenet rehearsal helper for deriving the Monero
  address controlled by a partial spend key plus a public Starknet secret.

## Files

- Config inventory:
  `/etc/atomic-swap/claim-relayer.config.json`
- Non-secret environment:
  `/etc/atomic-swap/claim-relayer.env`
- Secret partial-key environment:
  `/etc/atomic-swap/claim-relayer.secrets`
- Cursors:
  `/var/lib/atomic-swap/claim-relayer/cursors/*.json`
- Claim wallet-rpc log:
  `/var/log/atomic-swap/claim-wallet-rpc.log`

Use the templates in `ops/claim-relayer/` and `ops/systemd/`.
For operator takeover, use `docs/OPERATOR_HANDOFF.md`.
Use `ops/claim-relayer/claim-relayer-handoff-packet.py` to generate a redacted
handoff packet from the VM config and cursor state.
Use `ops/claim-relayer/verify-handoff-packet.py` on the receiving side before a
takeover; pass `--require-artifact` for production-like handoffs so the deployed
relayer binary checksum is always present.

## Config Model

Each enabled lock must have:

- `id`: stable human-readable lock id. This becomes the cursor filename when
  `cursor_path` is omitted.
- `contract_address`: AtomicLock contract address.
- `start_block`: deployment block, not block `0`.
- `restore_height`: Monero height before the swap output was funded.
- `partial_spend_key_env`: name of the environment variable holding that lock's
  32-byte partial spend key share.

The config intentionally stores the environment variable name, not the key
itself. Keep the actual key in `/etc/atomic-swap/claim-relayer.secrets` with
mode `0600`.

Registry discovery can be enabled with `discoveries[]`. Each discovery watches
an `AtomicLockFactory` contract for `AtomicLockRegistered` events and builds
lock entries automatically:

- `registry_address`: deployed factory/registry contract.
- `start_block`: factory deployment block or the first block to scan.
- `partial_key_env_prefix`: environment variable prefix. If the event emits
  `partial_key_id='smoke1'` and the prefix is `RELAYER_PARTIAL_`, the relayer
  expects `RELAYER_PARTIAL_SMOKE1` in `claim-relayer.secrets`.
- `restore_height` and `monero_network` come from the registry event.
- The discovered lock cursor still lives under `defaults.cursor_dir` and is
  independent per AtomicLock contract.

Manual `locks[]` entries remain supported and override duplicate discovered
contracts. This is useful for emergency pinning or one-off rehearsals.

## VM Install Shape

Inside the Monero VM:

```bash
id atomic-swap || sudo useradd --system --create-home --shell /usr/sbin/nologin atomic-swap
sudo install -d -o atomic-swap -g atomic-swap /etc/atomic-swap
sudo install -d -o atomic-swap -g atomic-swap /var/lib/atomic-swap/claim-relayer/cursors
sudo install -d -o atomic-swap -g atomic-swap /var/log/atomic-swap
sudo install -d -o atomic-swap -g atomic-swap /home/atomic-swap/.shared-ringdb
sudo install -d -o root -g root /opt/monero-starknet-atomic-swap/monero-bin
sudo install -d -o root -g root /opt/monero-starknet-atomic-swap/ops/claim-relayer

sudo cp ops/claim-relayer/claim-relayer.config.example.json \
  /etc/atomic-swap/claim-relayer.config.json
sudo cp ops/claim-relayer/claim-relayer.env.example \
  /etc/atomic-swap/claim-relayer.env
sudo cp ops/claim-relayer/claim-relayer.secrets.example \
  /etc/atomic-swap/claim-relayer.secrets
sudo chmod 600 /etc/atomic-swap/claim-relayer.secrets
sudo cp ops/claim-relayer/claim-relayer-healthcheck.env.example \
  /etc/atomic-swap/claim-relayer-healthcheck.env
sudo cp ops/claim-relayer/claim-relayer-healthcheck.sh \
  /opt/monero-starknet-atomic-swap/ops/claim-relayer/
sudo cp ops/claim-relayer/claim-relayer-alert.sh \
  /opt/monero-starknet-atomic-swap/ops/claim-relayer/
sudo cp ops/claim-relayer/configure-alert-destination.py \
  /opt/monero-starknet-atomic-swap/ops/claim-relayer/
sudo cp ops/claim-relayer/claim-relayer-handoff-packet.py \
  /opt/monero-starknet-atomic-swap/ops/claim-relayer/
sudo cp ops/claim-relayer/verify-handoff-packet.py \
  /opt/monero-starknet-atomic-swap/ops/claim-relayer/
sudo cp ops/claim-relayer/run-handoff-drill.sh \
  /opt/monero-starknet-atomic-swap/ops/claim-relayer/

sudo cp ops/systemd/monero-claim-wallet-rpc.service /etc/systemd/system/
sudo cp ops/systemd/monero-claim-wallet-rpc.env.example \
  /etc/atomic-swap/monero-claim-wallet-rpc.env
sudo cp ops/systemd/monero-claim-relayer.service /etc/systemd/system/
sudo cp ops/systemd/monero-claim-relayer-alert@.service /etc/systemd/system/
sudo cp ops/systemd/monero-claim-relayer-healthcheck.service /etc/systemd/system/
sudo cp ops/systemd/monero-claim-relayer-healthcheck.timer /etc/systemd/system/
sudo systemctl daemon-reload
```

Install `monero-wallet-rpc` into the root-owned `/opt` path used by the
systemd unit. Do not point the service at a symlink into a human user's home
directory; the `atomic-swap` system user may not be able to traverse it under
normal home-directory permissions.

```bash
sudo install -m 0755 -o root -g root /path/to/monero-wallet-rpc \
  /opt/monero-starknet-atomic-swap/monero-bin/monero-wallet-rpc
```

Build from the checked-out repo inside the VM:

```bash
cd /opt/monero-starknet-atomic-swap/rust
cargo build --release --bin claim_relayer_service --bin claim_revealed_secrets
```

Dry-run before enabling live claims:

```bash
target/release/claim_relayer_service \
  --config /etc/atomic-swap/claim-relayer.config.json \
  --dry-run \
  --once
```

Start the service:

```bash
sudo systemctl enable --now monero-claim-wallet-rpc.service
sudo systemctl enable --now monero-claim-relayer.service
sudo systemctl enable --now monero-claim-relayer-healthcheck.timer
sudo systemctl status monero-claim-relayer.service
journalctl -u monero-claim-relayer.service -f
```

## Cursor Rules

- Back up cursor files before deleting or editing them.
- A cursor advances only after a Monero claim succeeds.
- If wallet-rpc fails before sweep submission, retry with the same cursor.
- If wallet-rpc returns a sweep txid but the process dies before cursor write,
  verify the txid in the destination wallet before retrying. A second retry can
  safely fail with no spendable funds, but operators should not blindly delete
  cursors after a submitted sweep.
- Retained block hashes are used for short Starknet reorg detection. If a reorg
  changes a retained block, the relayer rewinds to the changed block and drops
  processed event ids at or after that block.

## Stuck Wallet-RPC Triage

If the claim wallet-rpc stops responding:

```bash
sudo systemctl restart monero-claim-wallet-rpc.service
sudo journalctl -u monero-claim-wallet-rpc.service -n 200
```

Then check for generated temporary wallets:

```bash
find /home/atomic-swap/monero-wallets -maxdepth 1 -name 'swap_*' -ls
```

Only remove `swap_*` wallets after confirming no sweep is still in progress.
The rehearsal showed a slow height-0 refresh could leave a large temporary
wallet cache; the current code refreshes from `restore_height` before sweeping.

## Health Checks

Minimum checks for an on-call rotation:

- `systemctl is-active monero-claim-relayer.service`
- `systemctl is-active monero-claim-wallet-rpc.service`
- `systemctl list-timers monero-claim-relayer-healthcheck.timer`
- `systemctl status monero-claim-relayer-healthcheck.service`
- cursor file `mtime` changes when new block ranges are processed
- log has recent `claim relayer service pass complete`
- no repeated `failed to load claim relayer config`
- no repeated `claim relayer lock pass failed`
- destination wallet sees expected incoming sweep txids

The timer-backed healthcheck in `ops/claim-relayer/claim-relayer-healthcheck.sh`
turns the minimum checks into a failing systemd unit. It validates JSON config,
enabled lock/discovery inventory, wallet-rpc liveness, cursor freshness, and
recent relayer/registry failure patterns in journald. For one-shot rehearsals,
set `RELAYER_EXPECT_ACTIVE=0` or `WALLET_RPC_EXPECT_ACTIVE=0` in
`/etc/atomic-swap/claim-relayer-healthcheck.env` as needed.

`monero-claim-relayer-healthcheck.service` has `OnFailure=` wired to
`monero-claim-relayer-alert@.service`. Set `RELAYER_ALERT_WEBHOOK_URL` in
`/etc/atomic-swap/claim-relayer-healthcheck.env` to send failures to the
operator alerting endpoint. For local rehearsals without a webhook, set
`RELAYER_ALERT_FILE=/var/log/atomic-swap/claim-relayer-alerts.jsonl` and invoke
`claim-relayer-alert.sh <failed-unit>`; the script appends the exact JSON
payload without sending it over the network. The alert service is hardened with
`ProtectSystem=strict` and allows writes only to `/var/log/atomic-swap` for the
local rehearsal sink.

Configure the production webhook without putting it in shell history:

```bash
read -rsp 'Relayer alert webhook URL: ' RELAYER_ALERT_WEBHOOK_URL
printf '\n'
printf '%s\n' "$RELAYER_ALERT_WEBHOOK_URL" | sudo \
  /opt/monero-starknet-atomic-swap/ops/claim-relayer/configure-alert-destination.py \
  --webhook-stdin \
  --clear-alert-file \
  --environment stagenet
unset RELAYER_ALERT_WEBHOOK_URL
sudo systemctl daemon-reload
sudo systemctl start monero-claim-relayer-alert@manual-rehearsal.service
sudo journalctl -u monero-claim-relayer-alert@manual-rehearsal.service -n 50 --no-pager
```

The helper updates `/etc/atomic-swap/claim-relayer-healthcheck.env` with mode
`0600` when the existing file is too permissive and prints only redacted status.
The manual rehearsal should deliver one alert to the real destination before
the timer is considered production-ready.

## Remaining Production Gap

Automatic discovery now exists as a factory/registry event path and has both a
Sepolia dry-run proof and a VM live Monero claim proof against factory
`0x053cb8c9c1590253eabf1fdd88ac6db975c5c91f4705c531b8c664a66b2e4c31`.
Before using it for meaningful value, configure the real alert webhook/paging
destination and rehearse the same path with production-like operator handoff.
