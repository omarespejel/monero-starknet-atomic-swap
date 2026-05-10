//! Sanitized frontend/API view over swap terms and internal state.
//!
//! This module deliberately exposes only public, UI-safe metadata. Secrets,
//! partial spend keys, view scalars, wallet files, webhook URLs, and account
//! keys must stay in operator artifacts, not in this view.

use serde::{Deserialize, Serialize};
use thiserror::Error;

use super::driver::GRACE_PERIOD_SECS;
use super::state::SwapState;
use super::terms::{
    Chain, StarknetPrivacySettlement, StarknetReceiveMode, SwapDirection, SwapTerms, SwapTermsError,
};

pub const PRIVACY_HELPER_ENTRYPOINT: &str = "privacy_invoke";

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SwapUiStep {
    StarknetEscrow,
    MoneroPayment,
    MoneroConfirmations,
    StarknetReveal,
    StarknetClaim,
    MoneroClaim,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SwapUiStepStatus {
    Pending,
    Active,
    Complete,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SwapUiProgressStep {
    pub step: SwapUiStep,
    pub status: SwapUiStepStatus,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SwapUiAction {
    WaitForStarknetEscrow,
    FundStarknetEscrow,
    SendMoneroPayment,
    WaitForCounterpartyMoneroPayment,
    WaitForMoneroConfirmations,
    RevealOnStarknet,
    WaitForGracePeriod,
    ClaimStarknetTokens,
    ClaimStarknetPrivacyNote,
    ClaimMonero,
    Done,
    Refunded,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct SwapPublicView {
    pub swap_id: String,
    pub direction: SwapDirection,
    pub user_sends: Chain,
    pub user_receives: Chain,
    pub monero_network: super::terms::MoneroNetwork,
    pub monero_amount_piconero: u64,
    pub starknet_amount: String,
    pub starknet_token: String,
    pub starknet_receive_mode: StarknetReceiveMode,
    pub state: String,
    pub terminal: bool,
    pub next_action: SwapUiAction,
    pub steps: Vec<SwapUiProgressStep>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub contract_address: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub lock_until: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub monero_txid: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub starknet_claimable_after: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub starknet_privacy_settlement: Option<StarknetPrivacySettlementView>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum StarknetPrivacySettlementStatus {
    OpenNotePlanned,
    HelperBound,
    Claimable,
    PrivateNoteFilled,
    Cancelled,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct StarknetPrivacySettlementView {
    pub privacy_pool_address: String,
    pub privacy_helper_address: String,
    pub open_note_id: String,
    pub open_note_token: String,
    pub open_note_amount: String,
    pub helper_entrypoint: String,
    pub status: StarknetPrivacySettlementStatus,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub helper_calldata: Option<Vec<String>>,
}

impl SwapPublicView {
    pub fn from_terms_state(terms: &SwapTerms, state: &SwapState) -> Result<Self, SwapViewError> {
        Self::from_terms_state_at(terms, state, None)
    }

    pub fn from_terms_state_at(
        terms: &SwapTerms,
        state: &SwapState,
        now: Option<u64>,
    ) -> Result<Self, SwapViewError> {
        terms.validate().map_err(SwapViewError::InvalidTerms)?;
        if terms.swap_id != state.swap_id() {
            return Err(SwapViewError::SwapIdMismatch {
                terms_swap_id: terms.swap_id.clone(),
                state_swap_id: state.swap_id().to_string(),
            });
        }

        Ok(Self {
            swap_id: terms.swap_id.clone(),
            direction: terms.direction,
            user_sends: terms.direction.user_sends(),
            user_receives: terms.direction.user_receives(),
            monero_network: terms.monero_network,
            monero_amount_piconero: terms.monero_amount_piconero,
            starknet_amount: terms.starknet_amount.to_string(),
            starknet_token: terms.starknet_token.clone(),
            starknet_receive_mode: terms.starknet_receive_mode,
            state: state_name(state).to_string(),
            terminal: state.is_terminal(),
            next_action: next_action(terms, state, now),
            steps: steps_for(terms.direction, state),
            contract_address: contract_address(state),
            lock_until: lock_until(state),
            monero_txid: monero_txid(state),
            starknet_claimable_after: starknet_claimable_after(state),
            starknet_privacy_settlement: starknet_privacy_settlement(terms, state, now),
        })
    }
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum SwapViewError {
    #[error("invalid swap terms: {0}")]
    InvalidTerms(SwapTermsError),
    #[error("swap id mismatch: terms={terms_swap_id}, state={state_swap_id}")]
    SwapIdMismatch {
        terms_swap_id: String,
        state_swap_id: String,
    },
}

fn state_name(state: &SwapState) -> &'static str {
    match state {
        SwapState::Created { .. } => "created",
        SwapState::StarknetLocked { .. } => "starknet_locked",
        SwapState::XmrSent { .. } => "xmr_sent",
        SwapState::XmrConfirmed { .. } => "xmr_confirmed",
        SwapState::SecretRevealed { .. } => "secret_revealed",
        SwapState::Completed { .. } => "completed",
        SwapState::Refunded { .. } => "refunded",
    }
}

fn state_rank(state: &SwapState) -> Option<u8> {
    match state {
        SwapState::Created { .. } => Some(0),
        SwapState::StarknetLocked { .. } => Some(1),
        SwapState::XmrSent { .. } => Some(2),
        SwapState::XmrConfirmed { .. } => Some(3),
        SwapState::SecretRevealed { .. } => Some(4),
        SwapState::Completed { .. } => Some(5),
        SwapState::Refunded { .. } => None,
    }
}

fn steps_for(direction: SwapDirection, state: &SwapState) -> Vec<SwapUiProgressStep> {
    let steps = match direction {
        SwapDirection::XmrToStarknet => vec![
            (SwapUiStep::StarknetEscrow, 1),
            (SwapUiStep::MoneroPayment, 2),
            (SwapUiStep::MoneroConfirmations, 3),
            (SwapUiStep::StarknetReveal, 4),
            (SwapUiStep::StarknetClaim, 5),
        ],
        SwapDirection::StarknetToXmr => vec![
            (SwapUiStep::StarknetEscrow, 1),
            (SwapUiStep::MoneroPayment, 2),
            (SwapUiStep::MoneroConfirmations, 3),
            (SwapUiStep::StarknetReveal, 4),
            (SwapUiStep::MoneroClaim, 5),
        ],
    };

    let rank = state_rank(state);
    steps
        .into_iter()
        .map(|(step, complete_at)| SwapUiProgressStep {
            step,
            status: step_status(rank, complete_at),
        })
        .collect()
}

fn step_status(rank: Option<u8>, complete_at: u8) -> SwapUiStepStatus {
    match rank {
        None => SwapUiStepStatus::Failed,
        Some(rank) if rank >= complete_at => SwapUiStepStatus::Complete,
        Some(rank) if rank + 1 == complete_at => SwapUiStepStatus::Active,
        Some(_) => SwapUiStepStatus::Pending,
    }
}

fn next_action(terms: &SwapTerms, state: &SwapState, now: Option<u64>) -> SwapUiAction {
    match state {
        SwapState::Created { .. } => match terms.direction {
            SwapDirection::XmrToStarknet => SwapUiAction::WaitForStarknetEscrow,
            SwapDirection::StarknetToXmr => SwapUiAction::FundStarknetEscrow,
        },
        SwapState::StarknetLocked { .. } => match terms.direction {
            SwapDirection::XmrToStarknet => SwapUiAction::SendMoneroPayment,
            SwapDirection::StarknetToXmr => SwapUiAction::WaitForCounterpartyMoneroPayment,
        },
        SwapState::XmrSent { .. } => SwapUiAction::WaitForMoneroConfirmations,
        SwapState::XmrConfirmed { .. } => SwapUiAction::RevealOnStarknet,
        SwapState::SecretRevealed {
            reveal_timestamp, ..
        } => match terms.direction {
            SwapDirection::StarknetToXmr => SwapUiAction::ClaimMonero,
            SwapDirection::XmrToStarknet => {
                let claimable_after = reveal_timestamp + GRACE_PERIOD_SECS;
                if now.is_some_and(|timestamp| timestamp >= claimable_after) {
                    starknet_claim_action(terms.starknet_receive_mode)
                } else {
                    SwapUiAction::WaitForGracePeriod
                }
            }
        },
        SwapState::Completed { .. } => SwapUiAction::Done,
        SwapState::Refunded { .. } => SwapUiAction::Refunded,
    }
}

fn starknet_claim_action(receive_mode: StarknetReceiveMode) -> SwapUiAction {
    match receive_mode {
        StarknetReceiveMode::PublicAddress => SwapUiAction::ClaimStarknetTokens,
        StarknetReceiveMode::PrivacyOpenNote => SwapUiAction::ClaimStarknetPrivacyNote,
    }
}

fn contract_address(state: &SwapState) -> Option<String> {
    match state {
        SwapState::StarknetLocked {
            contract_address, ..
        }
        | SwapState::XmrSent {
            contract_address, ..
        }
        | SwapState::XmrConfirmed {
            contract_address, ..
        }
        | SwapState::SecretRevealed {
            contract_address, ..
        } => Some(contract_address.clone()),
        _ => None,
    }
}

fn lock_until(state: &SwapState) -> Option<u64> {
    match state {
        SwapState::StarknetLocked { lock_until, .. }
        | SwapState::XmrSent { lock_until, .. }
        | SwapState::XmrConfirmed { lock_until, .. } => Some(*lock_until),
        _ => None,
    }
}

fn monero_txid(state: &SwapState) -> Option<String> {
    match state {
        SwapState::XmrSent { monero_txid, .. } | SwapState::XmrConfirmed { monero_txid, .. } => {
            Some(monero_txid.clone())
        }
        SwapState::SecretRevealed { monero_txid, .. } => monero_txid.clone(),
        SwapState::Completed { monero_txid, .. } => Some(monero_txid.clone()),
        _ => None,
    }
}

fn starknet_claimable_after(state: &SwapState) -> Option<u64> {
    match state {
        SwapState::SecretRevealed {
            reveal_timestamp, ..
        } => Some(reveal_timestamp + GRACE_PERIOD_SECS),
        _ => None,
    }
}

fn starknet_privacy_settlement(
    terms: &SwapTerms,
    state: &SwapState,
    now: Option<u64>,
) -> Option<StarknetPrivacySettlementView> {
    let settlement = terms.starknet_privacy_settlement.as_ref()?;
    Some(StarknetPrivacySettlementView {
        privacy_pool_address: settlement.privacy_pool_address.clone(),
        privacy_helper_address: settlement.privacy_helper_address.clone(),
        open_note_id: settlement.open_note_id.clone(),
        open_note_token: settlement.open_note_token.clone(),
        open_note_amount: settlement.open_note_amount.to_string(),
        helper_entrypoint: PRIVACY_HELPER_ENTRYPOINT.to_string(),
        status: privacy_settlement_status(state, now),
        helper_calldata: privacy_helper_calldata(settlement, state),
    })
}

fn privacy_helper_calldata(
    settlement: &StarknetPrivacySettlement,
    state: &SwapState,
) -> Option<Vec<String>> {
    contract_address(state).map(|atomic_lock| vec![atomic_lock, settlement.open_note_id.clone()])
}

fn privacy_settlement_status(
    state: &SwapState,
    now: Option<u64>,
) -> StarknetPrivacySettlementStatus {
    match state {
        SwapState::SecretRevealed {
            reveal_timestamp, ..
        } => {
            if now.is_some_and(|timestamp| timestamp >= reveal_timestamp + GRACE_PERIOD_SECS) {
                StarknetPrivacySettlementStatus::Claimable
            } else {
                StarknetPrivacySettlementStatus::HelperBound
            }
        }
        SwapState::Completed { .. } => StarknetPrivacySettlementStatus::PrivateNoteFilled,
        SwapState::Refunded { .. } => StarknetPrivacySettlementStatus::Cancelled,
        _ => StarknetPrivacySettlementStatus::OpenNotePlanned,
    }
}
