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

Known local result for Cairo: `113 passed, 0 failed, 0 ignored`.

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
- `AtomicLockFactory` adds the on-chain discovery surface that was missing from
  the explicit inventory model. Owner-only `register_lock` and `deploy_lock`
  emit `AtomicLockRegistered` with the AtomicLock address, partial-key id,
  Monero restore height, Monero network, and metadata hash.
- `claim_relayer_service` can now enable `discoveries[]` in
  `claim-relayer.config.json`. It scans finalized-enough factory events,
  derives per-lock entries, maps `partial_key_id` to deterministic secret env
  vars such as `RELAYER_PARTIAL_SMOKE1`, and still writes independent per-lock
  cursors.
- Sepolia factory/discovery smoke proof succeeded:
  - `AtomicLockFactory` class hash:
    `0x059efa4e6acec399f7d90128e934e0dbee93ad6c6201323eeed01a1847c49109`
  - factory declare tx:
    `0x035b44f42ed92ee7aff97fe42f858c3c7ffdcd5bf2e2b18bc089a980c98b8997`
  - factory contract:
    `0x053cb8c9c1590253eabf1fdd88ac6db975c5c91f4705c531b8c664a66b2e4c31`
  - factory deploy tx:
    `0x022e4cabc4d6d9de1561d3bddb12b39bc1e8cf601f0419ef27a6bdd5970c2c76`
  - factory-created zero-value AtomicLock:
    `0x013fd024676edb864c7918f1db05a28e97c3e7c9e702fb17d344434998572998`
  - `deploy_lock` tx:
    `0x069b5af6d6301acac17c830550617946e67bfbc190978aa7c668d393734777b1`,
    block `9572198`
  - registry metadata:
    `partial_key_id=factory1`, `restore_height=2115307`,
    `monero_network=stagenet`, `metadata_hash=0x1`
  - discovery-only dry-run from a fresh cursor found the lock and advanced its
    cursor:
    `latest_block=9572228`, `safe_tip=9572228`,
    `from_block=9572198`, `to_block=9572228`, `events_seen=1`,
    `reveals_claimed=0`, `events_skipped=1`, `enabled_locks=1`,
    `succeeded_locks=1`, `failed_locks=0`.
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
- VM systemd live-mode rehearsal succeeded with a fresh Sepolia STRK lock and a
  fresh stagenet-funded Monero swap output:
  - AtomicLock contract:
    `0x003b8269c53e2844c2d121894758123897f5e4e6bf24ccbf91b7a2e13d592673`
  - class hash:
    `0x01bb600e297a2c5daf1a0910221e69c6fe8531b4b35d377faf34a7ca41155750`
  - STRK token:
    `0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d`
  - amount:
    `100000000000000`
  - deploy tx:
    `0x07cd66dbba27a27e9a7d38b27bfc8888866baf079b7979eb796cefc04d90f878`
  - approve tx:
    `0x0149e34c91c8dde1102811aeea7b5520a8b751fa7b41ff018751be7f188780a9`
  - deposit tx:
    `0x0310cf32f1361c5100f15b7c088c632693b8c415884adcb9573b139ad09a0531`
  - reveal tx:
    `0x02a55bf0080b2ff5ace56020bb4468481caba0d3caedfe03a9360b6255a12200`
  - reveal receipt:
    `execution_status=SUCCEEDED`, `finality_status=ACCEPTED_ON_L2`,
    block `9570938`
  - Starknet token claimable after:
    `2026-05-09T09:07:47Z`
  - reveal event id:
    `9570938:0x2a55bf0080b2ff5ace56020bb4468481caba0d3caedfe03a9360b6255a12200:SecretRevealed`
  - post-reveal state before claim:
    `is_secret_revealed=true`, `is_unlocked=false`, contract STRK balance
    `100000000000000`
  - derived claim address funded:
    `59UGws6pmRqExoZcRJaKNyJLSdcDVzUhGNvNW6LNhSZJicFf6YC5xAT3CmeQtPuKS1ZHpNFveYE3PfW4TWTPV4Es6NwPFMf`
  - funding tx:
    `892bc303ebb60e9e179b7adfef1f1e1e5bb5647edc5f2a74fa11bfa42a5930ec`,
    amount `5000000000` atomic units (`0.005` stagenet XMR), fee
    `48320000` atomic units, mined at block `2115327`, unlocked at
    `11` confirmations.
  - supervised claim wallet-rpc:
    `monero-claim-wallet-rpc.service` ran under the `atomic-swap` system user
    on `127.0.0.1:38091`.
  - supervised relayer:
    `monero-claim-relayer.service` ran without `--dry-run` and exited with
    `Result=success`, `ExecMainCode=0`, `ExecMainStatus=0`,
    `ActiveState=inactive`, `SubState=dead`.
  - live claim pass:
    `latest_block=9571563`, `safe_tip=9571562`,
    `from_block=9570929`, `to_block=9570948`, `events_seen=1`,
    `reveals_claimed=1`, `events_skipped=0`,
    `enabled_locks=1`, `succeeded_locks=1`, `failed_locks=0`.
  - sweep tx:
    `601d913941e88dde5e3856fe51741ed3d711cdea7e281b328af8ed082d3c0401`,
    amount `4966510000` atomic units, fee `33490000` atomic units.
  - first mined sweep check: block `2115341`, `confirmations=1`,
    `double_spend_seen=false`, `locked=true` under the normal Monero recipient
    maturity window.
  - systemd cursor:
    `/var/lib/atomic-swap/claim-relayer/cursors/sepolia-strk-systemd-live-2026-05-09.json`
    persisted `next_block=9570949` and the processed `SecretRevealed` event id,
    owned by `atomic-swap:atomic-swap` with `0600` permissions.
  - post-claim cleanup check: no generated `swap_*` wallet files remained in
    `/home/atomic-swap/monero-wallets`.
  - after the proof, `monero-claim-wallet-rpc.service` was stopped and only the
    primary VM wallet RPC on `127.0.0.1:38090` remained listening.
  - Starknet STRK claim tx after `claimable_after`:
    `0x02934de665ab98df4470bae022a91d8cb540fde3bc0a27b92326724a1d670384`
  - post-claim Starknet validation:
    `is_secret_revealed=true`, `is_unlocked=true`, contract STRK balance `0`.
  - follow-up heartbeat `claim-fresh-sepolia-strk-atomic-lock` was moved to
    claim only the factory-created STRK lock after its Starknet
    `claimable_after` time.
- VM systemd live-mode rehearsal also succeeded through the new factory
  discovery path:
  - factory contract:
    `0x053cb8c9c1590253eabf1fdd88ac6db975c5c91f4705c531b8c664a66b2e4c31`
  - factory-created AtomicLock:
    `0x04eaeaa14eddb36fe12b740b4837fc038f928a21b6fce1a20cb086e8f67bb7ea`
  - registry metadata:
    `partial_key_id=factorylive1`, `restore_height=2115351`,
    `monero_network=stagenet`, `metadata_hash=0x2`
  - `deploy_lock` tx:
    `0x0363aef8cef3b90254b19748b2df5c033b3561889650945cedc9f1fe37aa679e`,
    block `9572346`
  - approve tx:
    `0x03747e9c26e4dcebc0d1ec7cf335b227c514e09472a4d2f49d3419a4afa211bd`
  - deposit tx:
    `0x00fe3092e1d25a0fd0c7736abf55cc87cda3ce9052f36d8aed3994b009f9c5b6`
  - reveal tx:
    `0x01c50ece662542eed45d4401b0dfec1d1047a2dbd2093f361df8ed56563d0ff8`,
    block `9572395`
  - Starknet token claimable after:
    `2026-05-09T10:09:49Z`
  - post-reveal state before token claim:
    `is_secret_revealed=true`, `is_unlocked=false`, contract STRK balance
    `100000000000000`
  - derived claim address funded:
    `529P2hogkScV4QqzFhUtm9RtLYe6chC6b3cTNGG4gLKQK2CeTHnApZTMrxkHkus4RH3apPkFca7EeRUGHMvyP4Jf1wRnyhU`
  - funding tx:
    `3e93a79a3353f1faa7291750422fe305bf8942710c231d7e8623a714e08fda81`,
    amount `5000000000` atomic units (`0.005` stagenet XMR), fee
    `48210000` atomic units, mined at block `2115353`, unlocked at
    `11` confirmations.
  - supervised claim wallet-rpc:
    `monero-claim-wallet-rpc.service` ran under the `atomic-swap` system user
    on `127.0.0.1:38091`.
  - supervised discovery relayer:
    `monero-claim-relayer.service` ran without `--dry-run`, discovered the
    lock from `AtomicLockRegistered`, and exited with `Result=success`,
    `ExecMainCode=0`, `ExecMainStatus=0`, `ActiveState=inactive`,
    `SubState=dead`.
  - live discovery claim pass:
    `latest_block=9572764`, `safe_tip=9572763`,
    `from_block=9572366`, `to_block=9572465`, `events_seen=1`,
    `reveals_claimed=1`, `events_skipped=0`,
    `enabled_locks=1`, `succeeded_locks=1`, `failed_locks=0`.
  - reveal event id:
    `9572395:0x1c50ece662542eed45d4401b0dfec1d1047a2dbd2093f361df8ed56563d0ff8:SecretRevealed`
  - sweep tx:
    `29da7541963a473bb1f3f45953c6bc4fd825c795c6887916ac4eb40ce733e884`,
    amount `4966510000` atomic units, fee `33490000` atomic units.
  - first mined sweep check: block `2115364`, `confirmations=1`,
    `double_spend_seen=false`, `locked=true` under the normal Monero recipient
    maturity window.
  - systemd cursor:
    `/var/lib/atomic-swap/claim-relayer/cursors/sepolia-factory-live-2026-05-09_0x4eaeaa14eddb36fe12b740b4837fc038f928a21b6fce1a20cb086e8f67bb7ea.json`
    persisted `next_block=9572466` and the processed `SecretRevealed` event id.
  - post-claim cleanup check: no generated `swap_*` wallet files remained in
    `/home/atomic-swap/monero-wallets`.
  - after the proof, `monero-claim-wallet-rpc.service` was stopped and only the
    primary VM wallet RPC on `127.0.0.1:38090` remained listening.
  - heartbeat `claim-fresh-sepolia-strk-atomic-lock` was updated to claim this
    factory-created STRK lock after its Starknet `claimable_after` time.
- Live-mode operations fixes from the rehearsal:
  - `monero-claim-wallet-rpc.service` now executes a root-owned
    `/opt/monero-starknet-atomic-swap/monero-bin/monero-wallet-rpc` binary
    instead of a symlink into a human user's home directory.
  - `/home/atomic-swap/.shared-ringdb` is created and allowed in
    `ReadWritePaths`, avoiding the non-fatal Monero ringdb initialization
    warning under `ProtectHome=read-only`.
- `docs/RELAYER_OPERATIONS.md` now documents install shape, dry-run-first
  startup, cursor backup/restore rules, stuck wallet-rpc triage, and health
  checks.
- `docs/OPERATOR_HANDOFF.md` defines the production-like handoff packet,
  receiver verification, dry-run-first takeover, live claim criteria, Starknet
  token claim closeout, and incident notes.
- `ops/claim-relayer/run-handoff-drill.sh` runs the receiver-side handoff
  rehearsal in the Monero VM: packet generation, verifier checks, healthcheck
  rehearsal, and a `claim_relayer_service --dry-run --once` pass using a
  temporary cursor directory.
  - VM validation succeeded: packet verification passed with the expected
    installed-copy warning, healthcheck rehearsal passed with `cursor_count=3`,
    relayer dry-run processed the factory-created STRK lock from temporary
    cursors, and the pass reported `enabled_locks=1`, `succeeded_locks=1`,
    `failed_locks=0`.
- `docs/EXTERNAL_REVIEW_PACKET.md` defines the review scope, explicit
  non-goals, required commands, VM checks, known follow-ups, and review
  questions for an external reviewer.
- `ops/claim-relayer/claim-relayer-handoff-packet.py` generates a redacted JSON
  handoff packet from the VM config, cursor files, systemd state, and deployed
  git commit. It reports partial-key environment variable names only, never
  partial spend key values or webhook secrets, and it reports secret env-file
  presence/mode without reading or hashing secret contents. If the installed VM
  tree is not a git checkout, the packet can include installed binary checksums
  with `--artifact`.
- `ops/claim-relayer/verify-handoff-packet.py` verifies the receiver-side
  packet shape before takeover. It rejects malformed packets, invalid cursor
  metadata, missing required artifact checksums when `--require-artifact` is
  set, obvious unredacted token-bearing URLs, and unsafe
  `claim-relayer.secrets` modes.
  - validation: local Python compile passed, a generated example handoff packet
    passed verifier checks, and the script was installed into the Monero VM.
    VM verification with `--require-artifact` passed against
    `/tmp/claim-relayer-handoff-verify.json`; the packet contained one expected
    warning for the installed non-git `/opt` tree and included the relayer
    artifact checksum.
  - VM validation against `/etc/atomic-swap/claim-relayer.config.json` succeeded:
    the Alchemy RPC key was redacted to `<redacted>`, warnings contained only
    `repo_root did not resolve to a git checkout; verify artifact checksums`,
    the packet found `3` cursor files, confirmed `claim-relayer.secrets` exists
    with mode `0600`, and `claim_relayer_service` was checksummed at
    `0a3d5949aec3819bb7409d138fdef325849ad11f7e5de4ed93557a55b921315f`.
- `ops/claim-relayer/claim-relayer-healthcheck.sh` plus
  `monero-claim-relayer-healthcheck.{service,timer}` add a VM-side monitoring
  hook for config parse failures, missing enabled inventory/discovery,
  wallet-rpc liveness, stale cursors, and recent relayer/registry failure
  patterns in journald. `monero-claim-relayer-alert@.service` is wired through
  `OnFailure=` and posts to `RELAYER_ALERT_WEBHOOK_URL` when configured.
  - validation: `bash -n` passed locally; VM run with one-shot rehearsal
    services marked inactive passed with `enabled_discoveries=1`,
    `cursor_count=3`, recent journal clean, and fresh cursor age under the
    configured threshold.
  - `systemd-analyze verify` passed in the VM after installing the scripts at
    `/opt/monero-starknet-atomic-swap/ops/claim-relayer/`.
- Legacy Monero demo transaction finalization is fail-closed:
  `rust/src/monero_full.rs` is gated behind `full-integration`, production
  claims use wallet-rpc, and the regression test
  `transaction_finalizer_fails_closed` confirms it refuses placeholder
  transaction hex.
- Stale ignored unlock gas test was removed from
  `test_integration_atomic_lock.cairo`; the active real-vector unlock/MSM test
  `test_msm_check_with_real_data` passes and reports
  `l2_gas: ~18449527`.
- Placeholder ignored multi-vector DLEQ tests were removed from
  `test_integration_dleq_multiple.cairo`; additional vectors should be added as
  real deployment tests when the generation pipeline emits multiple fixtures.
- Ignored constructor diagnostic duplicate was removed from
  `test_integration_constructor.cairo`; full constructor/DLEQ flow remains
  covered by `test_e2e_dleq`.
- The deterministic-address malicious token harness is active:
  `test_reentrancy_attack_blocked` deploys AtomicLock at the token's target
  address with `deploy_at`, confirms the malicious token reaches
  `ReentrancyGuard: reentrant call`, and passes with
  `l2_gas: ~20334837`.
- CI now pins Cairo jobs to Scarb `2.14.0` and Starknet Foundry `0.56.0`,
  runs the full Cairo suite, and fails if any ignored Cairo tests return.
- Tracked Starknet RPC defaults no longer embed private provider keys. Sepolia
  examples use the public Zan RPC v0.10 suffix, and operator scripts redact
  token-bearing RPC URLs before printing or writing deployment records.
- `tools/check_secret_hygiene.py` is wired into CI to reject tracked provider
  URLs with embedded API keys, tracked local secret filenames, and literal
  non-devnet private-key assignments.
- Generated Scarb cache files were removed from git tracking and
  `cairo/.scarb_cache/` is ignored going forward.
- `docs/SETUP.md` now marks Linux VM Monero as the required funded-swap path and
  demotes Docker/local Monero to legacy development use.

## Remaining Blockers

- Automatic lock discovery: factory/registry contract code, registry event
  decoding, relayer discovery config, focused tests, Sepolia factory deployment,
  factory-created lock deployment, discovery dry-run, and VM live Monero claim
  proof are done. Remaining production work is configuring the real alert
  webhook/paging destination and running a second-operator handoff drill with
  the redacted packet.
- Starknet test-token finalization: the fresh live-mode STRK lock has been
  claimed and verified on Sepolia; a follow-up heartbeat is scheduled for the
  remaining factory-created Sepolia STRK lock after its `claimable_after` time.
- External security review: required before any meaningful-value mainnet use.

## Explicit Non-Goals For This Stage

- No strkXMR launch.
- No mainnet deployment.
- No bridge custody design.
- No direct Monero daemon or wallet-rpc process on macOS.
