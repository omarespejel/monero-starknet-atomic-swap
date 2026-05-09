# Reveal Relayer Operations

This runbook is for the XMR-to-Starknet side. The reveal relayer waits for a
specific incoming Monero wallet-rpc transfer, verifies the amount,
confirmation depth, and unlock status, then reveals the Starknet AtomicLock
secret through the maintained `sncast` helper.

Do not run Monero daemons, wallet-rpc, or swap wallets on macOS. Run this flow
inside the Lima Monero VM or another dedicated Linux host.

## Model

The reveal relayer is intentionally a one-shot per swap:

- one systemd instance per swap id;
- one env file at `/etc/atomic-swap/reveal-relayer/<swap-id>.env`;
- one secret file referenced by `REVEAL_SECRET_FILE`;
- wallet-rpc evidence comes from `get_transfer_by_txid`;
- Starknet signing is delegated to `scripts/atomic_lock_sncast_ops.sh reveal`.

The env file must not contain the reveal secret. The service reads the secret
from a file and passes only that file path to the helper, so the secret does not
appear in the process command line, systemd env file, or journal.

## VM Install Shape

Inside the Monero VM:

```bash
id atomic-swap || sudo useradd --system --create-home --shell /usr/sbin/nologin atomic-swap
sudo install -d -o atomic-swap -g atomic-swap /etc/atomic-swap/reveal-relayer
sudo install -d -m 0700 -o atomic-swap -g atomic-swap /etc/atomic-swap/reveal-relayer/secrets
sudo install -d -o atomic-swap -g atomic-swap /var/lib/atomic-swap
sudo install -d -o atomic-swap -g atomic-swap /var/log/atomic-swap
sudo install -d -o atomic-swap -g atomic-swap /home/atomic-swap/.starknet_accounts
sudo install -d -o atomic-swap -g atomic-swap /home/atomic-swap/.snfoundry
sudo install -d -o root -g root /opt/monero-starknet-atomic-swap/ops/reveal-relayer

sudo cp ops/reveal-relayer/run-reveal-relayer.sh \
  /opt/monero-starknet-atomic-swap/ops/reveal-relayer/
sudo cp ops/reveal-relayer/reveal-relayer.env.example \
  /etc/atomic-swap/reveal-relayer/example.env
sudo cp ops/systemd/monero-reveal-relayer@.service /etc/systemd/system/
sudo cp ops/systemd/monero-reveal-relayer-alert@.service /etc/systemd/system/
sudo systemctl daemon-reload
```

Build the reveal binary from the VM checkout:

```bash
cd /opt/monero-starknet-atomic-swap/rust
cargo build --release --bin relay_reveal
```

## Per-Swap Setup

Create the secret file without putting the value in shell history:

```bash
sudo -u atomic-swap install -m 0600 /dev/null \
  /etc/atomic-swap/reveal-relayer/secrets/<swap-id>.secret
sudo -u atomic-swap sh -c 'stty -echo; printf "Reveal secret hex: " >&2; IFS= read -r s; stty echo; printf "\n" >&2; printf "%s\n" "$s" > /etc/atomic-swap/reveal-relayer/secrets/<swap-id>.secret'
```

Create `/etc/atomic-swap/reveal-relayer/<swap-id>.env` from
`ops/reveal-relayer/reveal-relayer.env.example` and fill in:

- `ATOMIC_SWAP_CONTRACT_ADDRESS`
- `ATOMIC_SWAP_TOKEN_ADDRESS`
- `MONERO_TXID`
- `EXPECTED_MONERO_AMOUNT_PICONERO`
- `REVEAL_SECRET_FILE`
- Starknet `SNCAST_ACCOUNT` / `SNCAST_ACCOUNTS_FILE`
- `MONERO_WALLET_RPC_URL`

Keep the env file mode at `0600` or `0640`. Keep the secret file at `0600`.

## Rehearsal

First run the one-shot in dry-run mode:

```bash
sudo sed -i.bak 's/^REVEAL_DRY_RUN=.*/REVEAL_DRY_RUN=1/' \
  /etc/atomic-swap/reveal-relayer/<swap-id>.env
sudo systemctl start monero-reveal-relayer@<swap-id>.service
sudo journalctl -u monero-reveal-relayer@<swap-id>.service -n 100 --no-pager
sudo sed -i 's/^REVEAL_DRY_RUN=.*/REVEAL_DRY_RUN=0/' \
  /etc/atomic-swap/reveal-relayer/<swap-id>.env
```

Expected dry-run result:

- wallet-rpc sees an inbound transfer;
- amount is at least `EXPECTED_MONERO_AMOUNT_PICONERO`;
- confirmations meet `MONERO_CONFIRMATIONS`;
- `unlock_time` is satisfied;
- the log says the dry-run completed without submitting Starknet reveal.

## Live Reveal

After the dry-run passes:

```bash
sudo systemctl start monero-reveal-relayer@<swap-id>.service
sudo journalctl -u monero-reveal-relayer@<swap-id>.service -f
```

Success requires:

- `Monero payment reached reveal threshold`;
- `sncast reveal helper` exits successfully;
- `scripts/atomic_lock_sncast_ops.sh state <atomic_lock>` shows
  `is_secret_revealed=true`;
- no reveal secret or ByteArray calldata chunks appear in logs.

## Alerting

`monero-reveal-relayer@.service` reuses the existing alert script through the
dedicated `monero-reveal-relayer-alert@.service` template. Set the FireHydrant
webhook in `/etc/atomic-swap/claim-relayer-healthcheck.env`; the reveal alert
unit overrides the component/source tags so failures route as reveal-relayer
failures.

## Mainnet

Mainnet reveal uses the same one-shot service, but the helper will only invoke
after a release-file check passes. The env file must include:

```bash
STARKNET_NETWORK=mainnet
STARKNET_RPC_URL=https://api.zan.top/public/starknet-mainnet/rpc/v0_10
ATOMIC_SWAP_MAINNET_RELEASE_FILE=/opt/monero-starknet-atomic-swap/docs/MAINNET_DUST_DEMO_QUOTE.json
ATOMIC_SWAP_ALLOW_MAINNET=mainnet-release-reviewed
```

The release JSON must bind `starknet_network=mainnet` and
`starknet_atomic_lock` to the exact contract passed to the helper. Keep this
file public and secret-free. Do not bypass the guard with ad hoc edits on the
VM.
