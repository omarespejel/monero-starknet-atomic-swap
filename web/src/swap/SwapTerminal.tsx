import { QRCodeSVG } from "qrcode.react";
import { useState } from "react";
import {
  actionLabel,
  formatStrkFromFri,
  formatXmrFromPiconero,
  secondsUntil,
  stepLabel,
  unixToClock,
} from "./format";
import { useSwap } from "./useSwap";
import type {
  StarknetPrivacyOpenNoteIntent,
  StarknetPrivacySettlementStatus,
  SwapQuote,
  SwapSession,
  SwapUiProgressStep,
} from "./types";

function DetailRow({ label, value, tone }: { label: string; value: string; tone?: "xmr" | "strk" | "ok" | "warn" }) {
  const toneClass = tone ? `${tone}-text` : undefined;
  return (
    <div className="row">
      <dt>{label}</dt>
      <dd className={toneClass}>{value}</dd>
    </div>
  );
}

function CopyButton({ value }: { value: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    await navigator.clipboard.writeText(value);
    setCopied(true);
    window.setTimeout(() => setCopied(false), 1_200);
  }

  return (
    <button className="copy-button" onClick={copy} type="button">
      {copied ? "Copied" : "Copy"}
    </button>
  );
}

function QuoteBox({ quote }: { quote: SwapQuote }) {
  return (
    <dl className="quote-box">
      <DetailRow
        label="Send"
        value={quote.send_asset === "XMR" ? formatXmrFromPiconero(quote.monero_amount_piconero) : formatStrkFromFri(quote.starknet_amount)}
        tone={quote.send_asset === "XMR" ? "xmr" : "strk"}
      />
      <DetailRow
        label="Receive"
        value={quote.receive_asset === "XMR" ? formatXmrFromPiconero(quote.monero_amount_piconero) : formatStrkFromFri(quote.starknet_amount)}
        tone={quote.receive_asset === "XMR" ? "xmr" : "strk"}
      />
      <DetailRow label="Rate" value={quote.rate_label} />
      <DetailRow label="Expires" value={secondsUntil(quote.expires_at)} tone="warn" />
      <DetailRow label="Confirmations" value={`${quote.monero_confirmations} Monero blocks`} />
    </dl>
  );
}

function privacyStatusLabel(status: StarknetPrivacySettlementStatus): string {
  switch (status) {
    case "open_note_planned":
      return "Open note planned";
    case "helper_bound":
      return "Helper bound";
    case "claimable":
      return "Claimable";
    case "private_note_filled":
      return "Private note filled";
    case "cancelled":
      return "Cancelled";
  }
}

function PrivacyIntentBox({ intent }: { intent: StarknetPrivacyOpenNoteIntent | null }) {
  if (!intent) {
    return (
      <div className="error-box">
        Private STRK note unavailable.
      </div>
    );
  }

  return (
    <dl className="details-box privacy-box">
      <DetailRow label="Private receive" value="STRK open note" tone="ok" />
      <DetailRow label="Pool" value={intent.privacy_pool_address} />
      <DetailRow label="Helper" value={intent.privacy_helper_address} />
      <DetailRow label="Open note" value={intent.open_note_id} />
      <DetailRow label="Source" value={intent.source === "mock" ? "Prototype" : "Privacy SDK"} />
    </dl>
  );
}

function ProgressList({ steps }: { steps: SwapUiProgressStep[] }) {
  return (
    <ul className="progress-list" aria-label="Swap progress">
      {steps.map((step) => (
        <li className={`progress-step ${step.status}`} key={step.step}>
          <span className="step-marker" aria-hidden="true" />
          <span>{stepLabel(step.step)}</span>
        </li>
      ))}
    </ul>
  );
}

function PaymentPanel({ session }: { session: SwapSession }) {
  if (!session.payment) {
    return null;
  }

  return (
    <div className="payment-layout">
      <div className="qr-wrap">
        <div className="qr-frame">
          <QRCodeSVG
            value={session.payment.uri}
            size={152}
            bgColor="#f0f0ee"
            fgColor="#070707"
            level="M"
          />
        </div>
      </div>
      <div className="payment-box">
        <div className="row">
          <dt>Monero address</dt>
          <dd><CopyButton value={session.payment.address} /></dd>
        </div>
        <div className="address">{session.payment.address}</div>
      </div>
      <dl className="details-box">
        <DetailRow label="Exact amount" value={formatXmrFromPiconero(session.payment.amount_piconero)} tone="xmr" />
        <DetailRow
          label="Confirmations"
          value={`${session.confirmations_seen ?? 0}/${session.quote.monero_confirmations}`}
        />
      </dl>
    </div>
  );
}

function SessionPanel({ session, onReset }: { session: SwapSession; onReset: () => void }) {
  const view = session.view;
  const showPayment = view.next_action === "send_monero_payment" || view.next_action === "wait_for_monero_confirmations";

  return (
    <div className="stack">
      <dl className="details-box">
        <DetailRow label="Status" value={actionLabel(view.next_action)} tone={view.terminal ? "ok" : undefined} />
        <DetailRow label="Swap" value={view.swap_id} />
        <DetailRow
          label="Receive mode"
          value={view.starknet_receive_mode === "privacy_open_note" ? "Private note" : "Public address"}
          tone={view.starknet_receive_mode === "privacy_open_note" ? "ok" : "warn"}
        />
        {view.lock_until ? (
          <DetailRow label="Refund window" value={`${secondsUntil(view.lock_until)} left`} tone="warn" />
        ) : null}
        {view.starknet_claimable_after ? (
          <DetailRow label="Claimable after" value={unixToClock(view.starknet_claimable_after)} />
        ) : null}
        {view.contract_address ? (
          <DetailRow label="Atomic lock" value={view.contract_address} />
        ) : null}
        {view.monero_txid ? (
          <DetailRow label="Monero tx" value={view.monero_txid} />
        ) : null}
      </dl>

      {view.starknet_privacy_settlement ? (
        <dl className="details-box privacy-box">
          <DetailRow
            label="Private STRK"
            value={privacyStatusLabel(view.starknet_privacy_settlement.status)}
            tone={view.starknet_privacy_settlement.status === "private_note_filled" ? "ok" : undefined}
          />
          <DetailRow label="Pool" value={view.starknet_privacy_settlement.privacy_pool_address} />
          <DetailRow label="Helper" value={view.starknet_privacy_settlement.privacy_helper_address} />
          <DetailRow label="Open note" value={view.starknet_privacy_settlement.open_note_id} />
          {view.starknet_privacy_settlement.helper_calldata ? (
            <DetailRow
              label="Invoke"
              value={`${view.starknet_privacy_settlement.helper_entrypoint}(${view.starknet_privacy_settlement.helper_calldata.join(", ")})`}
            />
          ) : null}
        </dl>
      ) : null}

      {showPayment ? <PaymentPanel session={session} /> : null}
      <ProgressList steps={view.steps} />

      {view.terminal ? (
        <button className="secondary-button" onClick={onReset} type="button">
          New swap
        </button>
      ) : null}
    </div>
  );
}

export function SwapTerminal() {
  const swap = useSwap();
  const sendAsset = swap.direction === "xmr_to_starknet" ? "XMR" : "STRK";
  const receivingPrivately = swap.direction === "xmr_to_starknet" && swap.receiveMode === "privacy_open_note";
  const canStart =
    Boolean(swap.quote) &&
    (swap.quote?.direction === "starknet_to_xmr"
      ? Boolean(swap.moneroReceiveAddress.trim())
      : swap.quote?.receive_mode === "privacy_open_note"
        ? Boolean(swap.privacyOpenNoteIntent)
        : Boolean(swap.publicStarknetAddress.trim()));

  return (
    <article className="terminal">
      <header className="terminal-header">
        <span>{swap.direction === "xmr_to_starknet" ? "XMR to STRK" : "STRK to XMR"}</span>
        <span className={`status-dot ${swap.session && !swap.error ? "active" : ""}`} aria-hidden="true" />
      </header>

      <div className="terminal-body">
        {swap.phase === "quote" ? (
          <form
            className="form-grid"
            onSubmit={(event) => {
              event.preventDefault();
              void swap.requestQuote();
            }}
          >
            <div className="direction-grid" role="tablist" aria-label="Swap direction">
              <button
                className={swap.direction === "xmr_to_starknet" ? "selected" : undefined}
                onClick={() => {
                  swap.setDirection("xmr_to_starknet");
                  swap.setReceiveMode("privacy_open_note");
                  swap.setAmount("0.005");
                }}
                type="button"
              >
                Into Starknet
              </button>
              <button
                className={swap.direction === "starknet_to_xmr" ? "selected" : undefined}
                onClick={() => {
                  swap.setDirection("starknet_to_xmr");
                  swap.setReceiveMode("public_address");
                  swap.setAmount("40");
                }}
                type="button"
              >
                To Monero
              </button>
            </div>

            <div className="field">
              <label htmlFor="swap-amount">You send</label>
              <div className="asset-input">
                <input
                  id="swap-amount"
                  className="amount-input"
                  inputMode="decimal"
                  min="0"
                  onChange={(event) => swap.setAmount(event.target.value)}
                  placeholder="0.0"
                  value={swap.amount}
                />
                <span className={`asset-label ${sendAsset === "XMR" ? "xmr" : "strk"}`}>{sendAsset}</span>
              </div>
            </div>

            {swap.direction === "xmr_to_starknet" ? (
              <div className="field">
                <label htmlFor="receive-mode">Receive</label>
                <select
                  id="receive-mode"
                  className="text-input"
                  onChange={(event) => swap.setReceiveMode(event.target.value === "public_address" ? "public_address" : "privacy_open_note")}
                  value={swap.receiveMode}
                >
                  <option value="privacy_open_note">Private STRK note</option>
                  <option value="public_address">Public Starknet address</option>
                </select>
              </div>
            ) : (
              <div className="field">
                <label htmlFor="monero-receive">Receive XMR at</label>
                <input
                  id="monero-receive"
                  className="text-input"
                  onChange={(event) => swap.setMoneroReceiveAddress(event.target.value)}
                  placeholder="Fresh Monero address"
                  value={swap.moneroReceiveAddress}
                />
              </div>
            )}

            <button className="primary-button" disabled={swap.loading || !swap.amount.trim()} type="submit">
              {swap.loading ? "Getting quote" : "Get quote"}
            </button>
          </form>
        ) : null}

        {swap.phase === "review" && swap.quote ? (
          <form
            className="form-grid"
            onSubmit={(event) => {
              event.preventDefault();
              void swap.startSwap();
            }}
          >
            <QuoteBox quote={swap.quote} />

            {swap.quote.direction === "xmr_to_starknet" && receivingPrivately ? (
              <PrivacyIntentBox intent={swap.privacyOpenNoteIntent} />
            ) : null}

            {swap.quote.direction === "xmr_to_starknet" && !receivingPrivately ? (
              <div className="field">
                <label htmlFor="public-address">Public Starknet address</label>
                <input
                  id="public-address"
                  className="text-input"
                  onChange={(event) => swap.setPublicStarknetAddress(event.target.value)}
                  placeholder="0x..."
                  value={swap.publicStarknetAddress}
                />
              </div>
            ) : null}

            {swap.quote.direction === "starknet_to_xmr" ? (
              <div className="field">
                <label htmlFor="review-monero-receive">Receive XMR at</label>
                <input
                  id="review-monero-receive"
                  className="text-input"
                  onChange={(event) => swap.setMoneroReceiveAddress(event.target.value)}
                  placeholder="Fresh Monero address"
                  value={swap.moneroReceiveAddress}
                />
              </div>
            ) : null}

            <button className="primary-button" disabled={swap.loading || !canStart} type="submit">
              {swap.loading ? "Starting swap" : "Start swap"}
            </button>
            <button className="secondary-button" onClick={swap.reset} type="button">
              Back
            </button>
          </form>
        ) : null}

        {swap.phase === "running" && swap.session ? (
          <SessionPanel session={swap.session} onReset={swap.reset} />
        ) : null}

        {swap.error ? <div className="error-box">Error: {swap.error}</div> : null}
      </div>

      <footer className="terminal-footer">
        <span>{swap.quote?.quote_id ?? "No quote"}</span>
        <span>{swap.session?.backend_mode ?? "api"}</span>
      </footer>
    </article>
  );
}
