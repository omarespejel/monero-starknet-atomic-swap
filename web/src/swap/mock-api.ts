import type {
  CreateSwapRequest,
  QuoteRequest,
  StarknetPrivacyOpenNoteIntent,
  StarknetReceiveMode,
  SwapApi,
  SwapDirection,
  SwapPublicView,
  SwapQuote,
  SwapSession,
  SwapUiProgressStep,
} from "./types";
import { xmrToPiconero } from "./format";
import { buildPrivacyInvokeCalldata, quotePrivacySettlement } from "./privacy";

const STRK_TOKEN = "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d";
const PRIVACY_POOL_ADDRESS =
  import.meta.env.VITE_STARKNET_PRIVACY_POOL_ADDRESS ??
  "0x40337b1af3c663e86e333bab5a4b28da8d4652a15a69beee2b677776ffe812a";
const PRIVACY_HELPER_ADDRESS =
  import.meta.env.VITE_ATOMIC_SWAP_PRIVACY_HELPER_ADDRESS ??
  "0x01eabf8c477f15519b24e0f57cc74657a6cf863d10027dab9b411ce73d784d8d";
const MOCK_ATOMIC_LOCK_ADDRESS =
  "0x01f84506b71bf584cbb1a0429c160a4c328942ab7f176c050b671670a4bb5d85";
const MOCK_MONERO_ADDRESS =
  "41wDTMA81r9KCyercwNTRTQHU9JPDB556NwYMH9UD1KRVSNXrJpCYBp7PCgWUVtCKW7AxiGsXMxdgJSwRzQL7GKf8UAwZhX";
const RATE_STRK_PER_XMR = 8000;
const STRK_SCALE = 10n ** 18n;
const LOCK_DURATION_SECS = 10_800;
const MONERO_CONFIRMATIONS = 10;
const GRACE_PERIOD_SECS = 7_200;

type StoredSwap = SwapSession & {
  created_at_ms: number;
  privacy_intent?: StarknetPrivacyOpenNoteIntent;
};

const quotes = new Map<string, SwapQuote>();
const swaps = new Map<string, StoredSwap>();

function delay() {
  return new Promise((resolve) => window.setTimeout(resolve, 250));
}

function id(prefix: string): string {
  return `${prefix}_${crypto.randomUUID().slice(0, 8)}`;
}

function quoteAmounts(direction: SwapDirection, amount: string) {
  if (direction === "xmr_to_starknet") {
    const piconero = xmrToPiconero(amount);
    if (!piconero) {
      throw new Error("Enter a valid XMR amount with up to 12 decimals.");
    }
    const strkWhole = Math.round((piconero / 1_000_000_000_000) * RATE_STRK_PER_XMR);
    return {
      monero_amount_piconero: piconero,
      starknet_amount: (BigInt(strkWhole) * STRK_SCALE).toString(),
    };
  }

  const strk = Number(amount);
  if (!Number.isFinite(strk) || strk <= 0) {
    throw new Error("Enter a valid STRK amount.");
  }

  return {
    monero_amount_piconero: Math.round((strk / RATE_STRK_PER_XMR) * 1_000_000_000_000),
    starknet_amount: (BigInt(Math.round(strk)) * STRK_SCALE).toString(),
  };
}

function buildSteps(direction: SwapDirection, rank: number | null): SwapUiProgressStep[] {
  const steps = direction === "xmr_to_starknet"
    ? ["starknet_escrow", "monero_payment", "monero_confirmations", "starknet_reveal", "starknet_claim"]
    : ["starknet_escrow", "monero_payment", "monero_confirmations", "starknet_reveal", "monero_claim"];

  return steps.map((step, index) => {
    if (rank === null) {
      return { step, status: "failed" };
    }
    if (rank > index) {
      return { step, status: "complete" };
    }
    if (rank === index) {
      return { step, status: "active" };
    }
    return { step, status: "pending" };
  }) as SwapUiProgressStep[];
}

function claimAction(receiveMode: StarknetReceiveMode) {
  return receiveMode === "privacy_open_note" ? "claim_starknet_privacy_note" : "claim_starknet_tokens";
}

function sameSettlement(
  quote: SwapQuote,
  intent: StarknetPrivacyOpenNoteIntent,
): boolean {
  const expected = quote.starknet_privacy_settlement;
  return Boolean(
    expected &&
    expected.privacy_pool_address === intent.privacy_pool_address &&
    expected.privacy_helper_address === intent.privacy_helper_address &&
    expected.open_note_token === intent.open_note_token &&
    expected.open_note_amount === intent.open_note_amount,
  );
}

function deriveView(session: StoredSwap, nowMs: number): SwapPublicView {
  const elapsed = nowMs - session.created_at_ms;
  const quote = session.quote;
  const lockUntil = Math.floor(session.created_at_ms / 1000) + LOCK_DURATION_SECS;
  const revealAt = Math.floor((session.created_at_ms + 18_000) / 1000);

  if (elapsed < 2_000) {
    return view(session, "starknet_locked", "send_monero_payment", 1, lockUntil);
  }
  if (elapsed < 7_000) {
    return view(session, "xmr_sent", "wait_for_monero_confirmations", 2, lockUntil, {
      monero_txid: "mock_monero_txid_waiting_for_backend",
    });
  }
  if (elapsed < 14_000) {
    return view(session, "xmr_confirmed", "reveal_on_starknet", 3, lockUntil, {
      monero_txid: "mock_monero_txid_waiting_for_backend",
    });
  }
  if (elapsed < 22_000) {
    return view(session, "secret_revealed", "wait_for_grace_period", 4, undefined, {
      monero_txid: "mock_monero_txid_waiting_for_backend",
      starknet_claimable_after: revealAt + GRACE_PERIOD_SECS,
    });
  }

  return view(session, "completed", quote.direction === "xmr_to_starknet" ? claimAction(quote.receive_mode) : "claim_monero", 5, undefined, {
    monero_txid: "mock_monero_txid_waiting_for_backend",
  });
}

function view(
  session: StoredSwap,
  state: string,
  nextAction: SwapPublicView["next_action"],
  rank: number,
  lockUntil?: number,
  extra?: Pick<SwapPublicView, "monero_txid" | "starknet_claimable_after">,
): SwapPublicView {
  const quote = session.quote;
  const starknetPrivacySettlement = session.privacy_intent
    ? {
        privacy_pool_address: session.privacy_intent.privacy_pool_address,
        privacy_helper_address: session.privacy_intent.privacy_helper_address,
        open_note_id: session.privacy_intent.open_note_id,
        open_note_token: session.privacy_intent.open_note_token,
        open_note_amount: session.privacy_intent.open_note_amount,
        helper_entrypoint: session.privacy_intent.helper_entrypoint,
        status: state === "completed"
          ? "private_note_filled" as const
          : state === "refunded"
            ? "cancelled" as const
            : state === "secret_revealed"
              ? "helper_bound" as const
              : "open_note_planned" as const,
        helper_calldata: buildPrivacyInvokeCalldata(session.privacy_intent, MOCK_ATOMIC_LOCK_ADDRESS),
      }
    : undefined;

  return {
    swap_id: session.swap_id,
    direction: quote.direction,
    user_sends: quote.direction === "xmr_to_starknet" ? "monero" : "starknet",
    user_receives: quote.direction === "xmr_to_starknet" ? "starknet" : "monero",
    monero_network: "mainnet",
    monero_amount_piconero: quote.monero_amount_piconero,
    starknet_amount: quote.starknet_amount,
    starknet_token: STRK_TOKEN,
    starknet_receive_mode: quote.receive_mode,
    state,
    terminal: state === "completed" || state === "refunded",
    next_action: state === "completed" ? "done" : nextAction,
    steps: buildSteps(quote.direction, rank),
    contract_address: MOCK_ATOMIC_LOCK_ADDRESS,
    lock_until: lockUntil,
    starknet_privacy_settlement: starknetPrivacySettlement,
    ...extra,
  };
}

export const mockSwapApi: SwapApi = {
  async quote(request: QuoteRequest) {
    await delay();
    const amounts = quoteAmounts(request.direction, request.amount);
    const quote: SwapQuote = {
      quote_id: id("quote"),
      direction: request.direction,
      receive_mode: request.receive_mode,
      send_asset: request.direction === "xmr_to_starknet" ? "XMR" : "STRK",
      receive_asset: request.direction === "xmr_to_starknet" ? "STRK" : "XMR",
      ...amounts,
      rate_label: "1 XMR = 8000 STRK",
      expires_at: Math.floor(Date.now() / 1000) + 120,
      lock_duration_secs: LOCK_DURATION_SECS,
      monero_confirmations: MONERO_CONFIRMATIONS,
      min_amount: request.direction === "xmr_to_starknet" ? "0.005 XMR" : "40 STRK",
      max_amount: request.direction === "xmr_to_starknet" ? "0.05 XMR" : "400 STRK",
      starknet_privacy_settlement: request.direction === "xmr_to_starknet" && request.receive_mode === "privacy_open_note"
        ? quotePrivacySettlement(
            PRIVACY_POOL_ADDRESS,
            PRIVACY_HELPER_ADDRESS,
            STRK_TOKEN,
            amounts.starknet_amount,
          )
        : undefined,
    };
    quotes.set(quote.quote_id, quote);
    return quote;
  },

  async createSwap(request: CreateSwapRequest) {
    await delay();
    const quote = quotes.get(request.quote_id);
    if (!quote) {
      throw new Error("Quote expired or unknown.");
    }
    if (quote.direction !== request.direction || quote.receive_mode !== request.receive_mode) {
      throw new Error("Quote terms changed. Request a new quote.");
    }
    if (request.receive_mode === "privacy_open_note") {
      if (!request.starknet_privacy_settlement?.open_note_id.trim()) {
        throw new Error("Private STRK open note id is required.");
      }
      if (!sameSettlement(quote, request.starknet_privacy_settlement)) {
        throw new Error("Private settlement metadata does not match the quote.");
      }
    }
    if (request.direction === "starknet_to_xmr" && !request.monero_receive_address?.trim()) {
      throw new Error("Monero receive address is required.");
    }

    const swapId = id("swap");
    const session = {
      swap_id: swapId,
      quote,
      view: {} as SwapPublicView,
      payment: quote.direction === "xmr_to_starknet"
        ? {
            address: MOCK_MONERO_ADDRESS,
            amount_piconero: quote.monero_amount_piconero,
            uri: `monero:${MOCK_MONERO_ADDRESS}?tx_amount=${quote.monero_amount_piconero / 1_000_000_000_000}`,
          }
        : undefined,
      confirmations_seen: 0,
      links: {},
      backend_mode: "mock" as const,
      created_at_ms: Date.now(),
      privacy_intent: request.starknet_privacy_settlement,
    };
    session.view = deriveView(session, session.created_at_ms);
    swaps.set(swapId, session);
    return session;
  },

  async getSwap(swapId: string) {
    await delay();
    const session = swaps.get(swapId);
    if (!session) {
      throw new Error("Unknown swap.");
    }
    const elapsed = Date.now() - session.created_at_ms;
    const confirmations = Math.min(MONERO_CONFIRMATIONS, Math.floor(Math.max(0, elapsed - 4_000) / 1_000));
    session.confirmations_seen = confirmations;
    session.view = deriveView(session, Date.now());
    return session;
  },
};
