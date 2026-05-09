# Production Readiness

Last updated: 2026-05-09.

This repository is a testnet audit candidate, not a mainnet release. Do not deploy
strkXMR or mainnet swap contracts from this tree without a separate green light,
funded testnet rehearsal, and external review.

## Current Safe Path

- Cairo `AtomicLock` uses two-phase reveal/claim. The legacy
  `verify_and_unlock` entrypoint is reveal-only and no longer transfers tokens.
- DLEQ proof verification is constructor-enforced and checks the full
  Poseidon challenge plus full u256 response.
- The second DLEQ generator is domain-separated and no longer `2 * G`.
- Deployment calldata must come from the canonical vector/hint pipeline:

```bash
cd rust
cargo test -q --test test_vectors generate_cairo_test_vectors -- --ignored --nocapture
cd ..
uv run --project tools python tools/regenerate_dleq_hints.py
python3 tools/generate_deploy_calldata.py \
  --network sepolia \
  --depositor 0x... \
  --token 0x... \
  --amount ...
```

- Constructor calldata includes an explicit `depositor`. Do not infer it from
  constructor caller: UDC deployments make the caller the UDC.
- Signed Starknet deployment/invokes should use `scripts/deploy_with_sncast.sh`
  or another signer that supports current V3 fee `resource_bounds`, including
  `l1_data_gas`. Rust macOS placeholder signatures are disabled.
- `scripts/deploy_with_sncast.sh` supports `ATOMIC_SWAP_CLASS_HASH` to deploy an
  already-declared class and `ATOMIC_SWAP_LOCK_UNTIL` for explicit timelocks.
- Post-deploy state, claim, and refund operations should use
  `scripts/atomic_lock_sncast_ops.sh state|claim|refund <contract>` for the
  Sepolia rehearsal path.
- Monero wallet-rpc must run inside the Lima VM. Use
  `scripts/monero_vm_tunnel.sh vm-address|vm-balance|vm-height` for normal
  checks. Use `start|smoke|stop` only for temporary host-side tests against the
  VM wallet.
- Claim-side secret relaying should use the durable Rust loop in
  `claim_revealed_secrets`. For live Monero claims, run it inside the Monero VM
  or another Linux environment that has local access to the wallet-rpc wallet
  directory; host-side RPC tunneling is only acceptable for dry-runs.

## Verified Locally

The latest local validation included:

```bash
cd cairo && snforge test --detailed-resources
cd rust && cargo test -q --lib
cd rust && cargo test -q --test dleq_properties
cd rust && cargo test -q --test integration_test
cd rust && cargo test -q --test handle_secret_revealed_test
cd rust && cargo test -q --lib swap::relayer
cd rust && cargo test -q --bin claim_relayer_service
cd rust && cargo check -q --bins
cd rust && cargo check -q --bin claim_revealed_secrets
cd rust && cargo check -q --bin claim_relayer_service
cd rust && cargo check -q --bin derive_claim_address
cd rust && cargo check -q --features full-integration --bins
limactl shell monero-stagenet -- bash -lc 'cd ~/atomic-swap-rust && . $HOME/.cargo/env && cargo check -q --bin claim_relayer_service'
bun build scripts/deploy.ts --outdir /tmp/atomic-deploy-check --target bun
bun build scripts/ts/src/deploy.ts --outdir /tmp/atomic-ts-deploy-check --target node
bash -n scripts/deploy_with_sncast.sh
bash -n scripts/atomic_lock_sncast_ops.sh
bash -n scripts/monero_vm_tunnel.sh
python3 -m json.tool ops/claim-relayer/claim-relayer.config.example.json >/tmp/claim-relayer-config-check.json
git diff --check
```

Known local result for Cairo: `109 passed, 0 failed, 7 ignored`.

Sepolia rehearsal:

- Address:
  `0x7b9a4f3ab819b42ceeddc18955c8109748bb599d26af48518b0b58d4e9fb9bd`
- Chain: `0x534e5f5345504f4c4941` (`SN_SEPOLIA`)
- Class hash:
  `0x5b4b537eaa2399e3aa99c4e2e0208ebd6c71bc1467938cd52c798c601e43564`
- Nonce observed during readiness check: `0x35`
- Live Sepolia class declared:
  `0x01bb600e297a2c5daf1a0910221e69c6fe8531b4b35d377faf34a7ca41155750`
- Live Sepolia contract deployed:
  `0x056874c6da7e5d485e337769d2267fc6a024a57df85b529d08f453e86b6a40aa`
- Declare tx:
  `0x06402db2a273ef88c473ffe267e796c0d90c50641d5dbffa24f2b33c069444a1`
- Deploy tx:
  `0x036688d2af1298b352b485a6d88befd502def4f090c9da3a739f7fb9a63994ba`
- Tiny STRK approve/deposit/reveal completed:
  - approve:
    `0x0043dadba9f98ba0696de887202b0ea71442ec82ef1d3f7735827221730ab14a`
  - deposit:
    `0x0584e31699da5cde93c894e4e64590796e144de3de9a94f718f42c3dc58d28c5`
  - reveal:
    `0x0032cbac1724052bf1553d7c34dc978b7049749e251e75d9fc8bff0cad642f02`
- Post-reveal checks: `is_secret_revealed=true`, contract STRK balance
  `100000000000000`, `claimable_after=2026-05-09T01:21:48Z`.
- Latest pre-claim state read through `scripts/atomic_lock_sncast_ops.sh state`:
  `is_secret_revealed=true`, `is_unlocked=false`, `get_claimable_after=0x69fe8c2c`,
  `get_lock_until=0x69fea809`, contract STRK balance `100000000000000`.
- Claim completed after the grace period:
  - claim tx:
    `0x06794394722fc53f8d6a84f77860c6b894e9ca42d0b7910191849025ce31cc2f`
  - receipt: `execution_status=SUCCEEDED`, `finality_status=ACCEPTED_ON_L2`,
    block `9562893`
  - post-claim state: `is_secret_revealed=true`, `is_unlocked=true`,
    contract STRK balance `0`
  - claim events included `Unlocked` and `TokensClaimed` from the AtomicLock
    contract.
- Live event-read check: reveal tx receipt block `9560016` contains
  `SecretRevealed` key
  `0x12b00cc9424076f159ea2bfaf31f1623bbaf9eb50fb183d5f0e69899e764cf0`,
  matching `starkli selector SecretRevealed`.
- Rust event tooling now has unit coverage for decoding `SecretRevealed` and
  `TokensClaimed`, plus extracting the full 32-byte `reveal_secret` ByteArray
  from both sncast-style and offset-style account calldata.
- Claim-side relayer dry-run against the live reveal event succeeded:
  - command shape:
    `cargo run -q --bin claim_revealed_secrets -- --dry-run --once --contract-address 0x056874c6da7e5d485e337769d2267fc6a024a57df85b529d08f453e86b6a40aa --start-block 9560010 --cursor-path /tmp/atomic-claim-dry-run.json --max-blocks-per-batch 20 --confirmation-depth 1`
  - observed event id:
    `9560016:0x32cbac1724052bf1553d7c34dc978b7049749e251e75d9fc8bff0cad642f02:SecretRevealed`
  - pass result after local secret-hash-word verification:
    `latest_block=9569262`, `safe_tip=9569261`,
    `from_block=9560010`, `to_block=9560029`, `events_seen=1`,
    `reveals_claimed=1`, `events_skipped=0`.
  - cursor persisted `next_block=9560030`, the processed event id, and
    retained block hashes for reorg validation.
- Claim-side relayer live Monero VM rehearsal succeeded against the same
  Sepolia reveal event:
  - command shape:
    `target/debug/claim_revealed_secrets --once --contract-address 0x056874c6da7e5d485e337769d2267fc6a024a57df85b529d08f453e86b6a40aa --start-block 9560010 --cursor-path /tmp/vm-live-claim-cursor.json --max-blocks-per-batch 20 --confirmation-depth 1 --wallet-rpc-url http://127.0.0.1:38091/json_rpc --daemon-rpc-url http://node2.monerodevs.org:38089/json_rpc --wallet-dir /home/espejelomar.linux/monero-wallets --monero-network stagenet --claim-destination 54SCqiAL4qNU3c6RNXFfz16c3EpS8HJehQHCRQXuvJZ3E3UJ5BcneuY6RKcFLUMQZagWvWXDT8r6MCnEotEK4EgKHfP9j43 --restore-height 2115270`
  - event id:
    `9560016:0x32cbac1724052bf1553d7c34dc978b7049749e251e75d9fc8bff0cad642f02:SecretRevealed`
  - pass result:
    `latest_block=9570047`, `safe_tip=9570046`,
    `from_block=9560010`, `to_block=9560029`, `events_seen=1`,
    `reveals_claimed=1`, `events_skipped=0`.
  - cursor persisted `next_block=9560030`, the processed event id, and
    retained block hashes for reorg validation.
- Zero-value refund rehearsal lock deployed with the same class hash:
  - contract:
    `0x0142fbaf19004601c5a6403743e4d86623a8b39b847d6c939dc374e28effbf59`
  - deploy tx:
    `0x065e967eea67608f0832c1a52d5fe7eb0d929d42c9dc3b41f6f618f7dba763dc`
  - state checked at `2026-05-09T01:24Z`: `is_secret_revealed=false`,
    `is_unlocked=false`, `claimable_after=0`
  - refundable after `lock_until=2026-05-09T02:46:36Z`.
  - refund tx:
    `0x01832ea702923bd8547053be920801b87d5e0c4007a83e536205693cb4264bfd`
  - refund receipt: `execution_status=SUCCEEDED`,
    `finality_status=ACCEPTED_ON_L2`, block `9564881`
  - post-refund state: `is_secret_revealed=false`, `is_unlocked=true`,
    `claimable_after=0`
- Important finding from live rehearsal: the first UDC deployment recorded the
  UDC as depositor when the constructor used `get_caller_address()`. The
  constructor now takes explicit `depositor` calldata and tests cover the new
  ABI.

Monero VM check:

- Lima VM: `monero-stagenet`
- Wallet RPC: running inside the VM on `127.0.0.1:38090`
- Claim rehearsal wallet RPC: used a separate temporary-wallet RPC inside the
  VM on `127.0.0.1:38091`, so live claim tests did not switch or close the
  primary funded wallet. It was stopped after the rehearsal.
- Host tunnel: temporary only; stopped after smoke tests
- Wallet RPC smoke test: passed
- Stagenet address:
  `54SCqiAL4qNU3c6RNXFfz16c3EpS8HJehQHCRQXuvJZ3E3UJ5BcneuY6RKcFLUMQZagWvWXDT8r6MCnEotEK4EgKHfP9j43`
- Faucet funding received:
  `e2e31591f738b1a84ed7763b5d7f8d30cfcb5e9a0f781f2a540e7d4d1bbb85b1`,
  amount `100000000000` atomic units (`0.1` stagenet XMR).
- VM-only spend rehearsal succeeded:
  - destination subaddress:
    `7AY2sdDv7nqWTjo479rbUfW42xEvf29oPXSeZAau5APjRdechzA8YB3D7yAALwG11LR5UMbAjsHjhaVRqsqyCne4Ni7npJh`
  - transfer tx:
    `fe88d22edaaf518e64ba130ea4f6022fe70e92ef5f2addf3295bd375c207740a`
  - amount `10000000000` atomic units (`0.01` stagenet XMR), fee
    `33440000` atomic units.
  - first mined check: block `2115280`, `confirmations=1`,
    `double_spend_seen=false`, wallet `blocks_to_unlock=9`.
  - post-submit wallet balance: `99966560000` atomic units total, `0`
    unlocked until the new outputs mature.
- VM-only swap-key claim rehearsal succeeded:
  - derived claim address funded:
    `56ZNLFB4Bbc18cFbcRSgJaGtaVc8GyisDA1VnanTs7aREB8ZsUxg67uJdX29wqinWfFfcVbbHzShMjbksYBvCj3uQ3xEz4R`
  - funding tx:
    `c91bb51f6f8e5a4544d0d267d3b39a0d685c7724fe17ff383a98a2f509c9d1c7`,
    amount `5000000000` atomic units (`0.005` stagenet XMR), fee
    `33380000` atomic units, mined at block `2115292`, unlocked at
    `10` confirmations.
  - `claim_revealed_secrets` recovered the full key from the Sepolia reveal
    secret plus the local partial key share inside the VM, generated a
    temporary wallet, refreshed from restore height `2115270`, swept the funds,
    closed the wallet, and securely deleted the generated wallet file.
  - sweep tx:
    `0d5185346c7dba43ead8db856a13e3a60da8188f5591cd3f84beecc7d3d7ff4a`,
    amount `4966490000` atomic units, fee `33510000` atomic units.
  - first mined sweep check: block `2115306`, `confirmations=1`,
    `double_spend_seen=false`, `locked=true` under the normal Monero recipient
    maturity window.
  - post-claim cleanup check: no generated `swap_*` wallet files remained in
    `/home/espejelomar.linux/monero-wallets`.
  - readiness finding resolved during rehearsal: claim wallet refresh must use
    the swap restore height, not height `0`; `refresh_from_height` is now used
    before `sweep_all`.

Operations artifacts:

- `claim_relayer_service` adds a long-running multi-lock service wrapper around
  the durable relayer. Each lock has its own cursor, restore height, and
  partial-key environment variable; a failing lock is logged without blocking
  later enabled locks unless `--fail-fast` is set.
- VM dry-run of `claim_relayer_service` against the Sepolia smoke lock
  succeeded with one enabled lock:
  - event id:
    `9560016:0x32cbac1724052bf1553d7c34dc978b7049749e251e75d9fc8bff0cad642f02:SecretRevealed`
  - pass result:
    `latest_block=9570559`, `safe_tip=9570558`,
    `from_block=9560010`, `to_block=9560029`, `events_seen=1`,
    `reveals_claimed=1`, `events_skipped=0`.
  - service result:
    `enabled_locks=1`, `succeeded_locks=1`, `failed_locks=0`.
- `ops/claim-relayer/claim-relayer.config.example.json` is the explicit lock
  inventory template. It stores environment variable names for partial keys, not
  the keys themselves.
- `ops/systemd/monero-claim-wallet-rpc.service` and
  `ops/systemd/monero-claim-relayer.service` provide VM-side service templates
  with restart policy, private temp dirs, strict system protection, and
  write-path restrictions for wallets, cursors, and logs.
- Systemd templates were syntax-checked in the Monero VM with
  `systemd-analyze verify --root=...` against a temporary root containing the
  expected binary and env-file paths.
- VM systemd dry-run install succeeded:
  - installed release binary:
    `/opt/monero-starknet-atomic-swap/rust/target/release/claim_relayer_service`
  - installed units:
    `monero-claim-relayer.service` and `monero-claim-wallet-rpc.service`
  - dry-run override:
    `/etc/systemd/system/monero-claim-relayer.service.d/dry-run.conf`
  - installed config:
    `/etc/atomic-swap/claim-relayer.config.json`
  - `systemd-analyze verify monero-claim-relayer.service monero-claim-wallet-rpc.service`
    succeeded in the VM after wiring the expected Monero binary path.
  - `systemctl start monero-claim-relayer.service` ran a one-shot dry-run and
    exited with `Result=success`, `ExecMainCode=0`, `ExecMainStatus=0`,
    `ActiveState=inactive`, `SubState=dead`.
  - journal result:
    `latest_block=9570818`, `safe_tip=9570817`,
    `from_block=9560010`, `to_block=9560029`, `events_seen=1`,
    `reveals_claimed=1`, `events_skipped=0`,
    `enabled_locks=1`, `succeeded_locks=1`, `failed_locks=0`.
  - systemd cursor:
    `/var/lib/atomic-swap/claim-relayer/cursors/sepolia-strk-smoke-2026-05-09.json`
    persisted `next_block=9560030` and the processed `SecretRevealed` event id,
    owned by `atomic-swap:atomic-swap` with `0600` permissions.
  - both installed units remained `disabled`, and only the primary VM wallet RPC
    on `127.0.0.1:38090` was listening after the dry-run.
- `docs/RELAYER_OPERATIONS.md` now documents install shape, dry-run-first
  startup, cursor backup/restore rules, stuck wallet-rpc triage, and health
  checks.
- `docs/SETUP.md` now marks Linux VM Monero as the required funded-swap path and
  demotes Docker/local Monero to legacy development use.

## Remaining Blockers

- Supervised live-mode relayer rehearsal: service code, inventory templates,
  systemd units, cursor rules, runbook, VM install, and supervised systemd
  dry-run are done. The remaining proof is a fresh stagenet-funded swap output
  plus a fresh Starknet reveal, claimed by `monero-claim-relayer.service`
  without `--dry-run` while `monero-claim-wallet-rpc.service` is supervised by
  systemd.
- Automatic lock discovery: current production path is an explicit lock
  inventory. Fully automatic discovery still needs a factory/registry contract
  that emits AtomicLock addresses and off-chain metadata for the matching
  partial-key environment.
- Monero transaction finalization: `rust/src/monero_full.rs` no longer returns
  placeholder transaction hex. Real spends must go through wallet-rpc/Monero
  transaction tooling.
- Remaining ignored Cairo tests: gas profile, multi-vector DLEQ expansion,
  deterministic-address malicious token harness, and one diagnostic constructor
  flow.
- External security review: required before any meaningful-value mainnet use.

## Explicit Non-Goals For This Stage

- No strkXMR launch.
- No mainnet deployment.
- No bridge custody design.
- No direct Monero daemon or wallet-rpc process on macOS.
