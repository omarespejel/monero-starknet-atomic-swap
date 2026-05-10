use xmr_secret_gen::swap::{
    Chain, MoneroNetwork, StarknetPrivacySettlement, StarknetReceiveMode, SwapDirection, SwapTerms,
    SwapTermsError, TERMS_DEFAULT_MONERO_CONFIRMATIONS,
};

fn valid_terms(direction: SwapDirection) -> SwapTerms {
    let receive_mode = match direction {
        SwapDirection::XmrToStarknet => StarknetReceiveMode::PrivacyOpenNote,
        SwapDirection::StarknetToXmr => StarknetReceiveMode::PublicAddress,
    };
    let starknet_token =
        "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d".to_string();
    let starknet_amount = 40_000_000_000_000_000_000;
    let starknet_privacy_settlement = match receive_mode {
        StarknetReceiveMode::PrivacyOpenNote => Some(StarknetPrivacySettlement {
            privacy_pool_address:
                "0x40337b1af3c663e86e333bab5a4b28da8d4652a15a69beee2b677776ffe812a".to_string(),
            privacy_helper_address:
                "0x1eabf8c477f15519b24e0f57cc74657a6cf863d10027dab9b411ce73d784d8d".to_string(),
            open_note_id: "0x1234".to_string(),
            open_note_token: starknet_token.clone(),
            open_note_amount: starknet_amount,
        }),
        StarknetReceiveMode::PublicAddress => None,
    };

    SwapTerms {
        swap_id: "quote-1".to_string(),
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
fn directions_encode_user_intent() {
    assert_eq!(SwapDirection::XmrToStarknet.user_sends(), Chain::Monero);
    assert_eq!(
        SwapDirection::XmrToStarknet.user_receives(),
        Chain::Starknet
    );
    assert!(SwapDirection::XmrToStarknet.user_receives_starknet_claim());
    assert!(!SwapDirection::XmrToStarknet.user_receives_monero_claim());

    assert_eq!(SwapDirection::StarknetToXmr.user_sends(), Chain::Starknet);
    assert_eq!(SwapDirection::StarknetToXmr.user_receives(), Chain::Monero);
    assert!(!SwapDirection::StarknetToXmr.user_receives_starknet_claim());
    assert!(SwapDirection::StarknetToXmr.user_receives_monero_claim());
}

#[test]
fn terms_enums_parse_cli_friendly_values() {
    assert_eq!(
        "xmr-to-starknet".parse::<SwapDirection>().unwrap(),
        SwapDirection::XmrToStarknet
    );
    assert_eq!(
        "starknet_to_monero".parse::<SwapDirection>().unwrap(),
        SwapDirection::StarknetToXmr
    );
    assert_eq!(
        "STAGENET".parse::<MoneroNetwork>().unwrap(),
        MoneroNetwork::Stagenet
    );
    assert_eq!(
        "private".parse::<StarknetReceiveMode>().unwrap(),
        StarknetReceiveMode::PrivacyOpenNote
    );
    assert!("bad-direction".parse::<SwapDirection>().is_err());
}

#[test]
fn terms_roundtrip_serializes_large_starknet_amount_as_string() {
    let terms = valid_terms(SwapDirection::XmrToStarknet);
    let json = serde_json::to_string(&terms).unwrap();

    assert!(json.contains("\"starknet_amount\":\"40000000000000000000\""));

    let parsed: SwapTerms = serde_json::from_str(&json).unwrap();
    assert_eq!(terms, parsed);
    parsed.validate().unwrap();
}

#[test]
fn terms_validation_rejects_unsafe_quotes() {
    let mut terms = valid_terms(SwapDirection::StarknetToXmr);

    terms.lock_duration_secs = 7_200;
    assert_eq!(
        terms.validate().unwrap_err(),
        SwapTermsError::LockDurationTooShort {
            actual: 7_200,
            minimum: 10_800
        }
    );

    terms = valid_terms(SwapDirection::StarknetToXmr);
    terms.monero_confirmations = TERMS_DEFAULT_MONERO_CONFIRMATIONS - 1;
    assert_eq!(
        terms.validate().unwrap_err(),
        SwapTermsError::InsufficientMoneroConfirmations {
            actual: TERMS_DEFAULT_MONERO_CONFIRMATIONS - 1,
            minimum: TERMS_DEFAULT_MONERO_CONFIRMATIONS
        }
    );

    terms = valid_terms(SwapDirection::StarknetToXmr);
    terms.starknet_token = "4718".to_string();
    assert_eq!(
        terms.validate().unwrap_err(),
        SwapTermsError::InvalidStarknetToken
    );
}

#[test]
fn terms_validation_requires_consistent_private_starknet_settlement() {
    let mut terms = valid_terms(SwapDirection::XmrToStarknet);
    terms.starknet_privacy_settlement = None;
    assert_eq!(
        terms.validate().unwrap_err(),
        SwapTermsError::MissingStarknetPrivacySettlement
    );

    terms = valid_terms(SwapDirection::XmrToStarknet);
    terms
        .starknet_privacy_settlement
        .as_mut()
        .unwrap()
        .open_note_token = "0x123".to_string();
    assert_eq!(
        terms.validate().unwrap_err(),
        SwapTermsError::PrivacyOpenNoteTokenMismatch
    );

    terms = valid_terms(SwapDirection::XmrToStarknet);
    terms
        .starknet_privacy_settlement
        .as_mut()
        .unwrap()
        .open_note_amount = 1;
    assert_eq!(
        terms.validate().unwrap_err(),
        SwapTermsError::PrivacyOpenNoteAmountMismatch
    );

    terms = valid_terms(SwapDirection::StarknetToXmr);
    terms.starknet_receive_mode = StarknetReceiveMode::PrivacyOpenNote;
    assert_eq!(
        terms.validate().unwrap_err(),
        SwapTermsError::PrivacyReceiveModeRequiresXmrToStarknet
    );

    terms = valid_terms(SwapDirection::StarknetToXmr);
    terms.starknet_privacy_settlement = Some(StarknetPrivacySettlement {
        privacy_pool_address: "0x1".to_string(),
        privacy_helper_address: "0x2".to_string(),
        open_note_id: "0x3".to_string(),
        open_note_token: terms.starknet_token.clone(),
        open_note_amount: terms.starknet_amount,
    });
    assert_eq!(
        terms.validate().unwrap_err(),
        SwapTermsError::UnexpectedStarknetPrivacySettlement
    );
}
