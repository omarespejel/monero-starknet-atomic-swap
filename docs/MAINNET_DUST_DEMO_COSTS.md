# Mainnet Dust Demo Cost Ledger

This ledger tracks only explicit mainnet actions for the STRK/XMR dust demo.
Do not record private keys, wallet files, webhook URLs, or token-bearing RPC
URLs here.

## Starknet Mainnet Account

- Account name: `atomic-mainnet-dust-2026-05-09`
- Account address:
  `0x679e5d1e49ec2da6bf2cc35d9d8ac783d97d94ceb51fdf75243eea03203ae6a`
- Account class hash:
  `0x5b4b537eaa2399e3aa99c4e2e0208ebd6c71bc1467938cd52c798c601e43564`
- Account type: OpenZeppelin
- Initial funding observed: `200 STRK`

## Cost Entries

| Date UTC | Action | Tx | Block | Fee | Balance After | Notes |
|---|---|---:|---:|---:|---:|---|
| 2026-05-09 | Deploy Starknet mainnet account | `0x04a85addd21f0eb320b9221922aef840a3b90c1439cb7e52e93e0bb8f81da896` | `9618520` | `0.046517507536942464 STRK` | `199.953482492463057536 STRK` | `execution_status=SUCCEEDED`, `finality_status=ACCEPTED_ON_L2` |
| 2026-05-09 | Declare `AtomicLock` | `0x03a3f6611cfd453482fc48ffd21377a3da6c10da01acd4ffb3a9dddb58dd1b47` | `9618825` | `56.222425786220576 STRK` | | class hash `0x01bb600e297a2c5daf1a0910221e69c6fe8531b4b35d377faf34a7ca41155750` |
| 2026-05-09 | Declare `AtomicLockFactory` | `0x03d7e871d35ab4fa200d3dbed3f4568d4400f92603b46b30d523342b2e9a4cc9` | `9618845` | `3.0730041820166143 STRK` | | class hash `0x059efa4e6acec399f7d90128e934e0dbee93ad6c6201323eeed01a1847c49109` |
| 2026-05-09 | Deploy `AtomicLockFactory` | `0x007c0913987ff37cd7ae9a052ddd2781483a6f3844498e1ec3e1d200303dd32e` | `9618854` | `0.045549102997472765 STRK` | | factory `0x07f72aa0685938f5c6744a76343b6e946dd5755096719e14c372411f27f12df0` |
| 2026-05-09 | Deploy mainnet dust `AtomicLock` via factory | `0x03d369b930632140fbefea0364feb9203984d232dbd354000091090d0651eb9e` | `9618888` | `1.8435631969256927 STRK` | | lock `0x01f84506b71bf584cbb1a0429c160a4c328942ab7f176c050b671670a4bb5d85` |
| 2026-05-09 | Approve `40 STRK` escrow | `0x0028c89e975bb7e526c8397abbbbc73fc943b35aa6608e4cf69d13dfc2382711` | `9618921` | `0.0322856303690953 STRK` | | spender is the mainnet dust `AtomicLock` |
| 2026-05-09 | Deposit `40 STRK` escrow | `0x014c3e58112380dc20103158b507f1f8a02e49c55cda0a8ca18d7e3583c10404` | `9618928` | `0.04718017706778135 STRK` | `98.689474416865826080 STRK` | lock balance verified as `40 STRK` |

## Mainnet Dust Lock

- Factory:
  `0x07f72aa0685938f5c6744a76343b6e946dd5755096719e14c372411f27f12df0`
- AtomicLock:
  `0x01f84506b71bf584cbb1a0429c160a4c328942ab7f176c050b671670a4bb5d85`
- STRK escrow: `40 STRK`
- XMR quote: `0.005 XMR`
- Rate: `8000 STRK per XMR`
- Monero funding address:
  `41wDTMA81r9KCyercwNTRTQHU9JPDB556NwYMH9UD1KRVSNXrJpCYBp7PCgWUVtCKW7AxiGsXMxdgJSwRzQL7GKf8UAwZhX`
- Monero restore height: `3670409`
- Monero claim destination in the VM:
  `42R4x42iivefebdJa7CZugP4u1ui4g2modjZGDB29wNifxdcuWK5d1aAmR1om2RwYN63ZnaLBpBmhB5YgSjhTeSDQbLm826`
- Lock expiry: `2026-05-10T17:56:17Z`
- Hashlock:
  `a80a87e3632599d1eaead88fd68f4b621bf0ea35acd126c9cdc7cd56524f5d09`
- Public quote:
  `docs/MAINNET_DUST_DEMO_QUOTE.json`
- VM private material:
  `/etc/atomic-swap/mainnet-dust-demo/`
- Relayer dry-run discovery:
  `enabled_locks=1`, `succeeded_locks=1`, `failed_locks=0`,
  `events_seen=1`, `reveals_claimed=0`, `events_skipped=1`.
- Read-only state check at `2026-05-09T21:06Z`:
  `is_secret_revealed=false`, `is_unlocked=false`,
  `get_claimable_after=0`, `get_lock_until=1778435777`, and contract STRK
  balance `40 STRK`.

## VM Reveal Relayer Prep

- Prepared in `monero-stagenet` Lima VM at `2026-05-09T21:21Z`.
- Synced `/opt/monero-starknet-atomic-swap` from the host checkout.
- Built Linux release binaries:
  `rust/target/release/relay_reveal` and
  `rust/target/release/swap_public_view`.
- Installed Starknet Foundry `sncast 0.56.0` for the `atomic-swap` user.
- Installed and verified:
  `monero-reveal-relayer@.service` and
  `monero-reveal-relayer-alert@.service`.
- Copied the Starknet mainnet account file into
  `/home/atomic-swap/.starknet_accounts/starknet_open_zeppelin_accounts.json`
  with `0600` permissions.
- Staged the reveal secret at
  `/etc/atomic-swap/reveal-relayer/secrets/mainnet-dust-demo.secret` with
  `0600` permissions.
- Staged disabled pending env:
  `/etc/atomic-swap/reveal-relayer/mainnet-dust-demo.env.pending`.
  This is not an active systemd env file; it must be copied to
  `mainnet-dust-demo.env` only after replacing `MONERO_TXID` with the real
  mainnet transaction id.
- Read-only VM state check confirmed:
  `is_secret_revealed=false`, `is_unlocked=false`,
  `get_claimable_after=0`, `get_lock_until=1778435777`, and contract STRK
  balance `40 STRK`.
- Mainnet wallet-rpc template installed and started at `2026-05-09T21:33Z`
  as `monero-wallet-rpc@mainnet.service`, bound to `127.0.0.1:18091`.
- The per-swap monitor wallet was generated/opened from VM-held swap key
  material, refreshed from restore height `3670409`, and verified against the
  public Monero funding address. Refresh result: `received_money=false`.
- The reveal relayer now supports wallet-scan mode, so the mainnet demo can
  proceed without requiring the sender to provide a Monero txid.
- Source `AtomicLock` now rejects reveals after `lock_until`. The already
  deployed mainnet dust lock predates that source fix, so the demo relayer must
  not be left running past the dust lock expiry. Future production/dust locks
  should be declared from the fixed class.
- Live VM service started at `2026-05-09T21:50Z`:
  `monero-reveal-relayer@mainnet-dust-demo.service`. It is in wallet-scan mode
  with `REVEAL_CLAIM_AFTER_REVEAL=1`, `REVEAL_DRY_RUN=0`, and a timeout set to
  stop roughly 10 minutes before the dust lock expiry. Journal currently shows
  no inbound Monero transfer visible.

## Current Totals

- Starknet fees spent: `61.31052558313417 STRK`
- Monero fees spent: `0 XMR`
- STRK principal escrowed: `40 STRK`
- XMR principal sent: `0 XMR`
