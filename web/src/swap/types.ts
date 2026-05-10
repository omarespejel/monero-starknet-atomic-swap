export type Chain = "monero" | "starknet";
export type MoneroNetwork = "mainnet" | "stagenet" | "testnet";
export type StarknetReceiveMode = "public_address" | "privacy_open_note";
export type SwapDirection = "xmr_to_starknet" | "starknet_to_xmr";

export type SwapUiStep =
  | "starknet_escrow"
  | "monero_payment"
  | "monero_confirmations"
  | "starknet_reveal"
  | "starknet_claim"
  | "monero_claim";

export type SwapUiStepStatus = "pending" | "active" | "complete" | "failed";

export type SwapUiAction =
  | "wait_for_starknet_escrow"
  | "fund_starknet_escrow"
  | "send_monero_payment"
  | "wait_for_counterparty_monero_payment"
  | "wait_for_monero_confirmations"
  | "reveal_on_starknet"
  | "wait_for_grace_period"
  | "claim_starknet_tokens"
  | "claim_starknet_privacy_note"
  | "claim_monero"
  | "done"
  | "refunded";

export type StarknetPrivacySettlementStatus =
  | "open_note_planned"
  | "helper_bound"
  | "claimable"
  | "private_note_filled"
  | "cancelled";

export interface StarknetPrivacySettlementQuote {
  privacy_pool_address: string;
  privacy_helper_address: string;
  open_note_token: string;
  open_note_amount: string;
  helper_entrypoint: "privacy_invoke";
}

export interface StarknetPrivacyOpenNoteIntent extends StarknetPrivacySettlementQuote {
  open_note_id: string;
  source: "privacy_sdk" | "mock";
}

export interface StarknetPrivacySettlementView extends StarknetPrivacySettlementQuote {
  open_note_id: string;
  status: StarknetPrivacySettlementStatus;
  helper_calldata?: string[];
}

export interface SwapUiProgressStep {
  step: SwapUiStep;
  status: SwapUiStepStatus;
}

export interface SwapPublicView {
  swap_id: string;
  direction: SwapDirection;
  user_sends: Chain;
  user_receives: Chain;
  monero_network: MoneroNetwork;
  monero_amount_piconero: number;
  starknet_amount: string;
  starknet_token: string;
  starknet_receive_mode: StarknetReceiveMode;
  state: string;
  terminal: boolean;
  next_action: SwapUiAction;
  steps: SwapUiProgressStep[];
  contract_address?: string;
  lock_until?: number;
  monero_txid?: string;
  starknet_claimable_after?: number;
  starknet_privacy_settlement?: StarknetPrivacySettlementView;
}

export interface QuoteRequest {
  direction: SwapDirection;
  amount: string;
  receive_mode: StarknetReceiveMode;
}

export interface SwapQuote {
  quote_id: string;
  direction: SwapDirection;
  receive_mode: StarknetReceiveMode;
  send_asset: "XMR" | "STRK";
  receive_asset: "XMR" | "STRK";
  monero_amount_piconero: number;
  starknet_amount: string;
  rate_label: string;
  expires_at: number;
  lock_duration_secs: number;
  monero_confirmations: number;
  min_amount: string;
  max_amount: string;
  starknet_privacy_settlement?: StarknetPrivacySettlementQuote;
}

export interface CreateSwapRequest {
  quote_id: string;
  direction: SwapDirection;
  receive_mode: StarknetReceiveMode;
  starknet_privacy_settlement?: StarknetPrivacyOpenNoteIntent;
  public_starknet_address?: string;
  monero_receive_address?: string;
}

export interface MoneroPaymentRequest {
  address: string;
  amount_piconero: number;
  uri: string;
}

export interface ExplorerLinks {
  starknet_contract?: string;
  starknet_tx?: string;
  monero_tx?: string;
}

export interface SwapSession {
  swap_id: string;
  quote: SwapQuote;
  view: SwapPublicView;
  payment?: MoneroPaymentRequest;
  confirmations_seen?: number;
  links?: ExplorerLinks;
  backend_mode?: "http" | "mock";
}

export interface SwapApi {
  quote(request: QuoteRequest, signal?: AbortSignal): Promise<SwapQuote>;
  createSwap(request: CreateSwapRequest, signal?: AbortSignal): Promise<SwapSession>;
  getSwap(swapId: string, signal?: AbortSignal): Promise<SwapSession>;
}
