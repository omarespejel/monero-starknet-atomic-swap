import type {
  StarknetPrivacyOpenNoteIntent,
  StarknetPrivacySettlementQuote,
  SwapQuote,
} from "./types";

export const PRIVACY_HELPER_ENTRYPOINT = "privacy_invoke";

declare global {
  interface Window {
    xmrStrkPreparePrivacyOpenNote?: (
      quote: SwapQuote,
    ) => Promise<StarknetPrivacyOpenNoteIntent> | StarknetPrivacyOpenNoteIntent;
  }
}

function randomFelt(): string {
  const bytes = new Uint8Array(31);
  crypto.getRandomValues(bytes);
  bytes[0] &= 0x7f;
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("");
  return `0x${hex.replace(/^0+/, "") || "1"}`;
}

export function prepareMockPrivacyOpenNoteIntent(
  quote: SwapQuote,
): StarknetPrivacyOpenNoteIntent | null {
  if (quote.receive_mode !== "privacy_open_note") {
    return null;
  }
  if (!quote.starknet_privacy_settlement) {
    throw new Error("Quote is missing private STRK settlement metadata.");
  }

  return {
    ...quote.starknet_privacy_settlement,
    helper_entrypoint: PRIVACY_HELPER_ENTRYPOINT,
    open_note_id: randomFelt(),
    source: "mock",
  };
}

export async function preparePrivacyOpenNoteIntent(
  quote: SwapQuote,
  options: { allowMock: boolean },
): Promise<StarknetPrivacyOpenNoteIntent | null> {
  if (quote.receive_mode !== "privacy_open_note") {
    return null;
  }
  if (window.xmrStrkPreparePrivacyOpenNote) {
    return window.xmrStrkPreparePrivacyOpenNote(quote);
  }
  if (options.allowMock) {
    return prepareMockPrivacyOpenNoteIntent(quote);
  }
  throw new Error("Privacy SDK open-note preparer is not configured.");
}

export function buildPrivacyInvokeCalldata(
  intent: Pick<StarknetPrivacyOpenNoteIntent, "open_note_id">,
  atomicLockAddress: string,
): string[] {
  return [atomicLockAddress, intent.open_note_id];
}

export function quotePrivacySettlement(
  privacy_pool_address: string,
  privacy_helper_address: string,
  open_note_token: string,
  open_note_amount: string,
): StarknetPrivacySettlementQuote {
  return {
    privacy_pool_address,
    privacy_helper_address,
    open_note_token,
    open_note_amount,
    helper_entrypoint: PRIVACY_HELPER_ENTRYPOINT,
  };
}
