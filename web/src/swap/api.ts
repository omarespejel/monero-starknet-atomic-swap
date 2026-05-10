import { mockSwapApi } from "./mock-api";
import type { CreateSwapRequest, QuoteRequest, SwapApi } from "./types";

const API_BASE = import.meta.env.VITE_SWAP_API_BASE?.replace(/\/$/, "");
const API_MODE = import.meta.env.VITE_SWAP_API_MODE;

async function requestJson<T>(
  path: string,
  init: RequestInit,
  signal?: AbortSignal,
): Promise<T> {
  if (!API_BASE) {
    throw new Error("VITE_SWAP_API_BASE is not configured.");
  }

  const response = await fetch(`${API_BASE}${path}`, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
    signal,
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(body || `Swap API returned ${response.status}`);
  }

  return response.json() as Promise<T>;
}

const httpSwapApi: SwapApi = {
  quote(request: QuoteRequest, signal?: AbortSignal) {
    return requestJson("/quotes", { method: "POST", body: JSON.stringify(request) }, signal);
  },
  createSwap(request: CreateSwapRequest, signal?: AbortSignal) {
    return requestJson("/swaps", { method: "POST", body: JSON.stringify(request) }, signal);
  },
  getSwap(swapId: string, signal?: AbortSignal) {
    return requestJson(`/swaps/${encodeURIComponent(swapId)}`, { method: "GET" }, signal);
  },
};

export function getSwapApi(): SwapApi {
  if (API_MODE === "mock" || !API_BASE) {
    return mockSwapApi;
  }
  return httpSwapApi;
}

export function getApiModeLabel(): string {
  if (API_MODE === "mock" || !API_BASE) {
    return "prototype backend";
  }
  return "live backend";
}

