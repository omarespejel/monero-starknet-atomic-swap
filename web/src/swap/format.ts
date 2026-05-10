import type { SwapUiAction, SwapUiStep } from "./types";

const PICONERO_PER_XMR = 1_000_000_000_000;
const STRK_DECIMALS = 18n;
const STRK_SCALE = 10n ** STRK_DECIMALS;

export function xmrToPiconero(input: string): number | null {
  const normalized = input.trim();
  if (!/^\d+(\.\d{0,12})?$/.test(normalized)) {
    return null;
  }

  const [whole, fraction = ""] = normalized.split(".");
  const paddedFraction = fraction.padEnd(12, "0");
  const amount = Number(whole) * PICONERO_PER_XMR + Number(paddedFraction);
  return Number.isSafeInteger(amount) && amount > 0 ? amount : null;
}

export function piconeroToXmr(amount: number): string {
  const whole = Math.floor(amount / PICONERO_PER_XMR);
  const fraction = String(amount % PICONERO_PER_XMR).padStart(12, "0");
  return `${whole}.${fraction.replace(/0+$/, "") || "0"}`;
}

export function formatXmrFromPiconero(amount: number): string {
  return `${piconeroToXmr(amount)} XMR`;
}

export function formatStrkFromFri(amount: string): string {
  const raw = BigInt(amount);
  const whole = raw / STRK_SCALE;
  const fraction = (raw % STRK_SCALE).toString().padStart(Number(STRK_DECIMALS), "0");
  const displayFraction = fraction.slice(0, 4).replace(/0+$/, "");
  return `${whole.toString()}${displayFraction ? `.${displayFraction}` : ""} STRK`;
}

export function unixToClock(timestamp: number): string {
  return new Date(timestamp * 1000).toLocaleString(undefined, {
    hour: "2-digit",
    minute: "2-digit",
    month: "short",
    day: "numeric",
  });
}

export function secondsUntil(timestamp: number): string {
  const diff = Math.max(0, timestamp * 1000 - Date.now());
  const hours = Math.floor(diff / 3_600_000);
  const minutes = Math.floor((diff % 3_600_000) / 60_000);
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  return `${minutes}m`;
}

export function actionLabel(action: SwapUiAction): string {
  switch (action) {
    case "wait_for_starknet_escrow":
      return "Preparing Starknet escrow";
    case "fund_starknet_escrow":
      return "Create Starknet escrow";
    case "send_monero_payment":
      return "Send exact Monero payment";
    case "wait_for_counterparty_monero_payment":
      return "Waiting for Monero payment";
    case "wait_for_monero_confirmations":
      return "Waiting for Monero confirmations";
    case "reveal_on_starknet":
      return "Revealing on Starknet";
    case "wait_for_grace_period":
      return "Waiting for claim window";
    case "claim_starknet_tokens":
      return "Claiming STRK";
    case "claim_starknet_privacy_note":
      return "Filling private note";
    case "claim_monero":
      return "Claiming XMR";
    case "done":
      return "Complete";
    case "refunded":
      return "Refunded";
  }
}

export function stepLabel(step: SwapUiStep): string {
  switch (step) {
    case "starknet_escrow":
      return "Starknet escrow";
    case "monero_payment":
      return "Monero payment";
    case "monero_confirmations":
      return "Monero confirmations";
    case "starknet_reveal":
      return "Starknet reveal";
    case "starknet_claim":
      return "Starknet claim";
    case "monero_claim":
      return "Monero claim";
  }
}

