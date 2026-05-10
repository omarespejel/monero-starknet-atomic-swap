# XMR / STRK Web

This frontend is a thin, privacy-first UI over the repo's backend-safe
`SwapPublicView` schema. It does not derive protocol state in the browser and it
does not store private keys, Monero wallet material, webhook URLs, or relayer
metadata.

## Run Locally

```bash
pnpm install
pnpm dev
```

Without `VITE_SWAP_API_BASE`, the app uses the explicit mock backend so UI work
can continue before the HTTP service is merged. The header and footer label this
as a prototype backend.

To point at a real backend:

```bash
VITE_SWAP_API_BASE=http://127.0.0.1:8787 pnpm dev
```

## API Contract

The real backend should be the only source of truth for quote terms, swap state,
addresses, confirmations, Starknet lock times, tx hashes, and refund/claim
status.

Expected endpoints:

- `POST /quotes`
- `POST /swaps`
- `GET /swaps/:swap_id`

The `GET /swaps/:swap_id` response should return `SwapSession`, where
`SwapSession.view` is the Rust `SwapPublicView` projection from
`rust/src/swap/view.rs`. Secrets, view-share scalars, partial spend keys, wallet
paths, account keys, and internal relayer state must never be included.

For `xmr_to_starknet` with `receive_mode=privacy_open_note`, the quote must
include `starknet_privacy_settlement`:

```json
{
  "privacy_pool_address": "0x...",
  "privacy_helper_address": "0x...",
  "open_note_token": "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
  "open_note_amount": "40000000000000000000",
  "helper_entrypoint": "privacy_invoke"
}
```

The browser must then prepare a privacy-pool open note and send the resulting
`open_note_id` back in `POST /swaps` under `starknet_privacy_settlement`. In
production, wire `window.xmrStrkPreparePrivacyOpenNote(quote)` to the StarkWare
privacy SDK. The SDK call should create or reserve the open note for the user's
private recipient and later build the pool `InvokeExternal` call:

```ts
{
  contractAddress: quote.starknet_privacy_settlement.privacy_helper_address,
  entrypoint: "privacy_invoke",
  calldata: [atomicLockAddress, openNoteId],
}
```

The mock backend generates a prototype open note id in memory only. A live
backend must reject mock/generated note ids unless the privacy SDK flow has
actually created or reserved that note.

## Privacy Rules

- Default XMR-to-Starknet settlement is `privacy_open_note`.
- Public Starknet receive addresses are an explicit fallback, not the default.
- Private settlement means helper-to-pool open-note fill, not public
  claim-then-deposit.
- No analytics SDKs.
- No `localStorage` persistence for swap identifiers, payment addresses, or
  note commitments.
- The UI should display exact Monero payment amounts from the backend and should
  never accept client-calculated rates as authoritative.
