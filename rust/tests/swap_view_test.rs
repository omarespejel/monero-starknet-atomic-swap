use xmr_secret_gen::swap::{
    MoneroNetwork, StarknetPrivacySettlement, StarknetPrivacySettlementStatus, StarknetReceiveMode,
    SwapDirection, SwapPublicView, SwapState, SwapUiAction, SwapUiStep, SwapUiStepStatus,
    SwapViewError, TERMS_DEFAULT_MONERO_CONFIRMATIONS,
};

fn terms(
    direction: SwapDirection,
    receive_mode: StarknetReceiveMode,
) -> xmr_secret_gen::swap::SwapTerms {
    let starknet_token =
        "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d".to_string();
    let starknet_amount = 40_000_000_000_000_000_000;
    let starknet_privacy_settlement = match (direction, receive_mode) {
        (SwapDirection::XmrToStarknet, StarknetReceiveMode::PrivacyOpenNote) => {
            Some(StarknetPrivacySettlement {
                privacy_pool_address:
                    "0x40337b1af3c663e86e333bab5a4b28da8d4652a15a69beee2b677776ffe812a".to_string(),
                privacy_helper_address:
                    "0x1eabf8c477f15519b24e0f57cc74657a6cf863d10027dab9b411ce73d784d8d".to_string(),
                open_note_id: "0x1234".to_string(),
                open_note_token: starknet_token.clone(),
                open_note_amount: starknet_amount,
            })
        }
        _ => None,
    };

    xmr_secret_gen::swap::SwapTerms {
        swap_id: "swap-1".to_string(),
        direction,
        monero_network: MoneroNetwork::Stagenet,
        monero_amount_piconero: 5_000_000_000,
        starknet_amount,
        starknet_token,
        lock_duration_secs: 10_800,
        monero_confirmations: TERMS_DEFAULT_MONERO_CONFIRMATIONS,
        starknet_receive_mode: receive_mode,
        starknet_privacy_settlement,
    }
}

#[test]
fn xmr_to_starknet_view_tells_user_to_send_monero_after_escrow() {
    let terms = terms(
        SwapDirection::XmrToStarknet,
        StarknetReceiveMode::PublicAddress,
    );
    let state = SwapState::StarknetLocked {
        swap_id: "swap-1".to_string(),
        contract_address: "0xabc".to_string(),
        lock_until: 1_000_000,
        expected_monero_amount: 5_000_000_000,
        hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
        monero_restore_height: Some(2_000_000),
    };

    let view = SwapPublicView::from_terms_state(&terms, &state).unwrap();

    assert_eq!(view.next_action, SwapUiAction::SendMoneroPayment);
    assert_eq!(view.contract_address.as_deref(), Some("0xabc"));
    assert_eq!(view.lock_until, Some(1_000_000));
    assert_eq!(
        view.steps[0],
        xmr_secret_gen::swap::SwapUiProgressStep {
            step: SwapUiStep::StarknetEscrow,
            status: SwapUiStepStatus::Complete
        }
    );
    assert_eq!(view.steps[1].status, SwapUiStepStatus::Active);
}

#[test]
fn starknet_to_xmr_view_waits_for_counterparty_monero_after_lock() {
    let terms = terms(
        SwapDirection::StarknetToXmr,
        StarknetReceiveMode::PublicAddress,
    );
    let state = SwapState::StarknetLocked {
        swap_id: "swap-1".to_string(),
        contract_address: "0xabc".to_string(),
        lock_until: 1_000_000,
        expected_monero_amount: 5_000_000_000,
        hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
        monero_restore_height: Some(2_000_000),
    };

    let view = SwapPublicView::from_terms_state(&terms, &state).unwrap();

    assert_eq!(
        view.next_action,
        SwapUiAction::WaitForCounterpartyMoneroPayment
    );
    assert_eq!(view.steps.last().unwrap().step, SwapUiStep::MoneroClaim);
}

#[test]
fn privacy_mode_changes_post_grace_starknet_claim_action() {
    let terms = terms(
        SwapDirection::XmrToStarknet,
        StarknetReceiveMode::PrivacyOpenNote,
    );
    let state = SwapState::SecretRevealed {
        swap_id: "swap-1".to_string(),
        contract_address: "0xabc".to_string(),
        reveal_timestamp: 1_000,
        monero_txid: Some("xmr-tx".to_string()),
        monero_amount: Some(5_000_000_000),
        monero_restore_height: Some(2_000_000),
        partial_spend_key: Some([0x42; 32]),
        claim_destination: Some("54...".to_string()),
    };

    let waiting = SwapPublicView::from_terms_state_at(&terms, &state, Some(1_000)).unwrap();
    assert_eq!(waiting.next_action, SwapUiAction::WaitForGracePeriod);
    assert_eq!(waiting.starknet_claimable_after, Some(8_200));

    let claimable = SwapPublicView::from_terms_state_at(&terms, &state, Some(8_200)).unwrap();
    assert_eq!(
        claimable.next_action,
        SwapUiAction::ClaimStarknetPrivacyNote
    );
    let settlement = claimable.starknet_privacy_settlement.as_ref().unwrap();
    assert_eq!(
        settlement.status,
        StarknetPrivacySettlementStatus::Claimable
    );
    assert_eq!(settlement.helper_entrypoint, "privacy_invoke");
    assert_eq!(
        settlement.helper_calldata,
        Some(vec!["0xabc".to_string(), "0x1234".to_string()])
    );

    let json = serde_json::to_string(&claimable).unwrap();
    assert!(!json.contains("partial_spend_key"));
    assert!(!json.contains("claim_destination"));
    assert!(!json.contains("42424242"));
}

#[test]
fn view_rejects_swap_id_mismatch() {
    let terms = terms(
        SwapDirection::XmrToStarknet,
        StarknetReceiveMode::PublicAddress,
    );
    let state = SwapState::Created {
        swap_id: "other-swap".to_string(),
        lock_duration_secs: 10_800,
        amount: 40_000_000_000_000_000_000,
        expected_monero_amount: 5_000_000_000,
        hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
        monero_restore_height: Some(2_000_000),
    };

    assert!(matches!(
        SwapPublicView::from_terms_state(&terms, &state).unwrap_err(),
        SwapViewError::SwapIdMismatch { .. }
    ));
}
