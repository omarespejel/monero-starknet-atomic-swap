# Atomic Swap Operator Handoff

This checklist is for a second operator taking over a Starknet-to-Monero claim
relayer run. It assumes Monero operations run inside the Linux VM, not on
macOS.

## Handoff Packet

The outgoing operator must provide:

- Git commit deployed to the VM.
- Starknet network and RPC endpoint.
- `AtomicLockFactory` address when registry discovery is used.
- Factory deployment block or explicit lock deployment block.
- AtomicLock address for any manual emergency lock entry.
- Starknet token address and expected escrow amount.
- Monero network, restore height, and destination address.
- Partial-key environment variable name, not the key value.
- Funding txid for the Monero swap output.
- Reveal tx hash and expected `SecretRevealed` block.
- Current cursor path and backup location.
- Healthcheck status and alert endpoint status.

Do not send private keys, partial spend keys, wallet files, or webhook secrets in
chat. The receiving operator should read those from the VM-local root-owned env
files.

## Receiver Verification

On the VM:

```bash
sudo systemctl status monero-claim-wallet-rpc.service
sudo systemctl status monero-claim-relayer.service
sudo systemctl status monero-claim-relayer-healthcheck.service
sudo /opt/monero-starknet-atomic-swap/ops/claim-relayer/claim-relayer-healthcheck.sh
sudo find /var/lib/atomic-swap/claim-relayer/cursors -maxdepth 1 -type f -ls
sudo find /home/atomic-swap/monero-wallets -maxdepth 1 -name 'swap_*' -ls
```

From the repo checkout, verify the Starknet side:

```bash
ATOMIC_SWAP_TOKEN_ADDRESS=<strk_token> \
  scripts/atomic_lock_sncast_ops.sh state <atomic_lock>
```

Expected pre-claim state for a revealed funded lock:

- `is_secret_revealed=true`
- `is_unlocked=false`
- `token balance_of(contract)` equals the escrow amount
- `get_claimable_after` is in the future or already passed

## Dry-Run First

For a registry-discovered lock, use a temporary cursor directory before touching
production cursors:

```bash
sudo -u atomic-swap env \
  RELAYER_CONFIG=/etc/atomic-swap/claim-relayer.config.json \
  /opt/monero-starknet-atomic-swap/rust/target/release/claim_relayer_service \
    --config /etc/atomic-swap/claim-relayer.config.json \
    --dry-run \
    --once
```

Confirm the log shows the discovered lock id and no failed lock pass.

## Live Claim

Only start live claim after the Monero funding tx is mined, mature, and not
double-spent:

```bash
sudo systemctl start monero-claim-wallet-rpc.service
sudo systemctl start monero-claim-relayer.service
sudo journalctl -u monero-claim-relayer.service -f
```

Success requires:

- `Monero claim submitted for revealed Starknet secret`
- a non-dry-run Monero sweep txid
- `reveals_claimed=1`
- `enabled_locks=1`, `succeeded_locks=1`, `failed_locks=0`
- cursor contains the processed `SecretRevealed` event id
- no `swap_*` wallets remain after cleanup

## Starknet Token Claim

After `claimable_after`, claim the Starknet escrow:

```bash
ATOMIC_SWAP_TOKEN_ADDRESS=<strk_token> \
  scripts/atomic_lock_sncast_ops.sh claim <atomic_lock>
```

Post-claim checks:

- `is_unlocked=true`
- contract token balance is zero
- claim tx hash is recorded in `docs/PRODUCTION_READINESS.md`

## Incident Notes

- If Monero sweep txid was emitted but cursor was not written, verify the sweep
  tx in the destination wallet before retrying.
- If wallet-rpc is stuck, restart only `monero-claim-wallet-rpc.service` first
  and inspect generated `swap_*` wallets before deleting anything.
- If registry discovery fails, pin the affected lock in `locks[]` with the same
  restore height and partial-key env var, then rerun a dry-run pass.
- If healthcheck alerting fires, preserve the journal and cursor file before
  editing config.
