# External Review Packet

This packet is for a security reviewer evaluating the testnet-ready
Monero-Starknet atomic swap core. It is not a mainnet approval packet.

Do not deploy `strkXMR` or mainnet contracts from this tree without a separate
green light, a funded testnet rehearsal, alerting configured, and external
review closeout.

## Scope

Review these surfaces first:

- Cairo contracts in `cairo/src/lib.cairo`, especially `AtomicLock`,
  `AtomicLockFactory`, constructor DLEQ verification, two-phase reveal/claim,
  refund paths, token transfer handling, and reentrancy protection.
- Cairo tests under `cairo/tests/`, especially real-vector DLEQ tests,
  two-phase unlock tests, token-security tests, and factory tests.
- Rust relayer code in `rust/src/swap/relayer.rs`,
  `rust/src/bin/claim_revealed_secrets.rs`, and
  `rust/src/bin/claim_relayer_service.rs`.
- Starknet event parsing and registry discovery in `rust/src/starknet.rs`.
- Operational scripts under `scripts/`, `ops/claim-relayer/`, and
  `ops/systemd/`.
- Readiness evidence in `docs/PRODUCTION_READINESS.md`,
  `docs/RELAYER_OPERATIONS.md`, and `docs/OPERATOR_HANDOFF.md`.

## Out Of Scope

- `strkXMR` token launch.
- Mainnet deployment.
- Privacy-pool integration.
- Bridge custody design.
- Production paging endpoint selection. The repo has alert hooks, but the real
  webhook/paging destination is operator-specific.

## Known Required Follow-Ups

- Rotate any Starknet RPC provider key that was ever committed in historical
  testnet rehearsal defaults. The latest tree removes tracked provider tokens,
  but history should be treated as exposed. Use
  `docs/SECRET_ROTATION_RUNBOOK.md` and attach the redacted
  `tools/check_secret_hygiene.py --history --report-only` output as evidence.
- Run a second-operator handoff drill using
  `ops/claim-relayer/claim-relayer-handoff-packet.py` and
  `ops/claim-relayer/verify-handoff-packet.py --require-artifact`, then attach
  the signoff record from `docs/OPERATOR_HANDOFF.md`.
- Confirm the FireHydrant alert destination remains configured in the Monero VM
  and that the latest manual rehearsal alert reached the `Atomic Swap Ops`
  route before enabling timer-backed production monitoring.

## Required Commands

Run these from the repository root unless noted.

```bash
git status --short --branch
python3 tools/readiness_preflight.py --output /tmp/atomic-swap-readiness-preflight.json
python3 tools/check_secret_hygiene.py
python3 tools/check_secret_hygiene.py --history --report-only
git diff --check

cd cairo
snforge test

cd ../rust
cargo test -q --lib
cargo test -q --test dleq_properties
cargo test -q --test integration_test
cargo test -q --test handle_secret_revealed_test
cargo test -q --lib swap::relayer
cargo test -q --bin claim_relayer_service
cargo check -q --bins
cargo check -q --features full-integration --bins
```

Expected current Cairo result: `113 passed, 0 failed, 0 ignored`.

## VM Checks

Monero-funded paths must run inside the Linux VM, not on macOS:

```bash
limactl list
limactl shell monero-stagenet -- bash -lc \
  'cd ~/atomic-swap-rust && . "$HOME/.cargo/env" && cargo check -q --bin claim_relayer_service'
```

For a handoff packet generated inside the VM:

```bash
/opt/monero-starknet-atomic-swap/ops/claim-relayer/verify-handoff-packet.py \
  --require-artifact \
  /tmp/claim-relayer-handoff.json
```

## Review Questions

- Is constructor-time DLEQ verification sufficient to bind the Starknet lock to
  the Monero adaptor/claim path without any alternate unlock path?
- Are all refund, reveal, claim, timeout, wrong-secret, bad-proof, and
  reentrancy cases covered by deterministic tests?
- Can registry discovery or cursor rewind behavior duplicate, skip, or
  prematurely advance a Monero claim under RPC errors or Starknet reorgs?
- Do generated claim-wallet files, partial spend keys, webhook URLs, and
  Starknet account keys stay out of logs, handoff packets, and tracked files?
- Does the operator runbook give enough information for a second operator to
  safely take over without receiving secrets in chat?

## Evidence Pointers

- Sepolia deploy/reveal/claim/refund evidence:
  `docs/PRODUCTION_READINESS.md`.
- Monero VM funded-claim rehearsals:
  `docs/PRODUCTION_READINESS.md`.
- Relayer operations:
  `docs/RELAYER_OPERATIONS.md`.
- Handoff process:
  `docs/OPERATOR_HANDOFF.md`.
- Secret rotation:
  `docs/SECRET_ROTATION_RUNBOOK.md`.
