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

## Privacy Rules

- Default XMR-to-Starknet settlement is `privacy_open_note`.
- Public Starknet receive addresses are an explicit fallback, not the default.
- No analytics SDKs.
- No `localStorage` persistence for swap identifiers, payment addresses, or
  note commitments.
- The UI should display exact Monero payment amounts from the backend and should
  never accept client-calculated rates as authoritative.

