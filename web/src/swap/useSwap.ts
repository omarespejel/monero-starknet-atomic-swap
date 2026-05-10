import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { getSwapApi } from "./api";
import { preparePrivacyOpenNoteIntent } from "./privacy";
import type {
  CreateSwapRequest,
  QuoteRequest,
  StarknetPrivacyOpenNoteIntent,
  StarknetReceiveMode,
  SwapDirection,
  SwapQuote,
  SwapSession,
} from "./types";

type UiPhase = "quote" | "review" | "running";
const ALLOW_MOCK_PRIVACY_INTENT =
  import.meta.env.VITE_SWAP_API_MODE === "mock" || !import.meta.env.VITE_SWAP_API_BASE;

interface UseSwapState {
  direction: SwapDirection;
  setDirection: (direction: SwapDirection) => void;
  receiveMode: StarknetReceiveMode;
  setReceiveMode: (mode: StarknetReceiveMode) => void;
  amount: string;
  setAmount: (amount: string) => void;
  privacyOpenNoteIntent: StarknetPrivacyOpenNoteIntent | null;
  publicStarknetAddress: string;
  setPublicStarknetAddress: (address: string) => void;
  moneroReceiveAddress: string;
  setMoneroReceiveAddress: (address: string) => void;
  phase: UiPhase;
  quote: SwapQuote | null;
  session: SwapSession | null;
  loading: boolean;
  error: string | null;
  requestQuote: () => Promise<void>;
  startSwap: () => Promise<void>;
  reset: () => void;
}

export function useSwap(): UseSwapState {
  const api = useMemo(() => getSwapApi(), []);
  const abortRef = useRef<AbortController | null>(null);
  const [direction, setDirection] = useState<SwapDirection>("xmr_to_starknet");
  const [receiveMode, setReceiveMode] = useState<StarknetReceiveMode>("privacy_open_note");
  const [amount, setAmount] = useState("0.005");
  const [privacyOpenNoteIntent, setPrivacyOpenNoteIntent] =
    useState<StarknetPrivacyOpenNoteIntent | null>(null);
  const [publicStarknetAddress, setPublicStarknetAddress] = useState("");
  const [moneroReceiveAddress, setMoneroReceiveAddress] = useState("");
  const [phase, setPhase] = useState<UiPhase>("quote");
  const [quote, setQuote] = useState<SwapQuote | null>(null);
  const [session, setSession] = useState<SwapSession | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const requestQuote = useCallback(async () => {
    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    setLoading(true);
    setError(null);
    try {
      const request: QuoteRequest = {
        direction,
        amount,
        receive_mode: direction === "xmr_to_starknet" ? receiveMode : "public_address",
      };
      const nextQuote = await api.quote(request, controller.signal);
      const nextPrivacyIntent = await preparePrivacyOpenNoteIntent(nextQuote, {
        allowMock: ALLOW_MOCK_PRIVACY_INTENT,
      });
      setQuote(nextQuote);
      setPrivacyOpenNoteIntent(nextPrivacyIntent);
      setPhase("review");
    } catch (err) {
      if (!controller.signal.aborted) {
        setError(err instanceof Error ? err.message : "Failed to request quote.");
      }
    } finally {
      if (!controller.signal.aborted) {
        setLoading(false);
      }
    }
  }, [amount, api, direction, receiveMode]);

  const startSwap = useCallback(async () => {
    if (!quote) {
      return;
    }

    abortRef.current?.abort();
    const controller = new AbortController();
    abortRef.current = controller;
    setLoading(true);
    setError(null);
    try {
      const request: CreateSwapRequest = {
        quote_id: quote.quote_id,
        direction: quote.direction,
        receive_mode: quote.receive_mode,
        starknet_privacy_settlement: quote.receive_mode === "privacy_open_note"
          ? privacyOpenNoteIntent ?? undefined
          : undefined,
        public_starknet_address: quote.receive_mode === "public_address" ? publicStarknetAddress : undefined,
        monero_receive_address: quote.direction === "starknet_to_xmr" ? moneroReceiveAddress : undefined,
      };
      const nextSession = await api.createSwap(request, controller.signal);
      setSession(nextSession);
      setPhase("running");
    } catch (err) {
      if (!controller.signal.aborted) {
        setError(err instanceof Error ? err.message : "Failed to start swap.");
      }
    } finally {
      if (!controller.signal.aborted) {
        setLoading(false);
      }
    }
  }, [api, moneroReceiveAddress, privacyOpenNoteIntent, publicStarknetAddress, quote]);

  useEffect(() => {
    if (!session || session.view.terminal) {
      return;
    }

    const controller = new AbortController();
    const timer = window.setInterval(async () => {
      try {
        const nextSession = await api.getSwap(session.swap_id, controller.signal);
        setSession(nextSession);
      } catch (err) {
        if (!controller.signal.aborted) {
          setError(err instanceof Error ? err.message : "Failed to refresh swap.");
        }
      }
    }, 2_000);

    return () => {
      controller.abort();
      window.clearInterval(timer);
    };
  }, [api, session]);

  const reset = useCallback(() => {
    abortRef.current?.abort();
    setPhase("quote");
    setQuote(null);
    setPrivacyOpenNoteIntent(null);
    setSession(null);
    setError(null);
  }, []);

  return {
    direction,
    setDirection,
    receiveMode,
    setReceiveMode,
    amount,
    setAmount,
    privacyOpenNoteIntent,
    publicStarknetAddress,
    setPublicStarknetAddress,
    moneroReceiveAddress,
    setMoneroReceiveAddress,
    phase,
    quote,
    session,
    loading,
    error,
    requestQuote,
    startSwap,
    reset,
  };
}
