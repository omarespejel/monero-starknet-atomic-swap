use xmr_secret_gen::swap::{
    Chain, MoneroNetwork, StarknetReceiveMode, SwapDirection, SwapTerms, SwapTermsError,
    TERMS_DEFAULT_MONERO_CONFIRMATIONS,
};

fn valid_terms(direction: SwapDirection) -> SwapTerms {
    SwapTerms {
        swap_id: "quote-1".to_string(),
        direction,
        monero_network: MoneroNetwork::Stagenet,
        monero_amount_piconero: 5_000_000_000,
        starknet_amount: 40_000_000_000_000_000_000,
        starknet_token: "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d"
            .to_string(),
        lock_duration_secs: 10_800,
        monero_confirmations: TERMS_DEFAULT_MONERO_CONFIRMATIONS,
        starknet_receive_mode: StarknetReceiveMode::PrivacyOpenNote,
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
