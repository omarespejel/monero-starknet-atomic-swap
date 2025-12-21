use xmr_secret_gen::swap::{SwapState, SwapDb, JsonFileDb};

#[test]
fn test_swap_state_serialization() {
    let state = SwapState::Created {
        swap_id: "test-123".to_string(),
        lock_duration_secs: 10800,
        amount: 1000000000000000000,
        expected_monero_amount: 1_000_000_000,
        hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
        monero_restore_height: Some(1000),
    };
    let json = serde_json::to_string(&state).unwrap();
    let parsed: SwapState = serde_json::from_str(&json).unwrap();
    assert_eq!(state, parsed);
}

#[test]
fn test_json_file_db_roundtrip() {
    let tmp = tempfile::tempdir().unwrap();
    let db = JsonFileDb::new(tmp.path()).unwrap();

    let state = SwapState::XmrSent {
        swap_id: "test-456".to_string(),
        contract_address: "0xabc".to_string(),
        lock_until: 9999999999,
        monero_txid: "monero_tx_123".to_string(),
        monero_amount: 1_000_000_000,
    };

    db.save(&state).unwrap();
    let loaded = db.load("test-456").unwrap().unwrap();
    assert_eq!(state, loaded);
}

#[test]
fn test_swap_id_accessor() {
    let state = SwapState::Created {
        swap_id: "test-789".to_string(),
        lock_duration_secs: 10800,
        amount: 1000000000000000000,
        expected_monero_amount: 1_000_000_000,
        hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
        monero_restore_height: Some(1000),
    };
    assert_eq!(state.swap_id(), "test-789");
}

#[test]
fn test_is_terminal() {
    let completed = SwapState::Completed {
        swap_id: "test-completed".to_string(),
        starknet_tx: "0xtx123".to_string(),
        monero_txid: "monero_tx_123".to_string(),
    };
    assert!(completed.is_terminal());

    let refunded = SwapState::Refunded {
        swap_id: "test-refunded".to_string(),
        reason: "Timeout".to_string(),
        refund_tx: Some("0xtx456".to_string()),
    };
    assert!(refunded.is_terminal());

    let created = SwapState::Created {
        swap_id: "test-created".to_string(),
        lock_duration_secs: 10800,
        amount: 1000000000000000000,
        expected_monero_amount: 1_000_000_000,
        hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
        monero_restore_height: Some(1000),
    };
    assert!(!created.is_terminal());
}

#[test]
fn test_all_state_variants_serialize() {
    let states = vec![
        SwapState::Created {
            swap_id: "test1".to_string(),
            lock_duration_secs: 10800,
            amount: 1000,
            expected_monero_amount: 1_000_000_000,
            hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
            monero_restore_height: Some(1000),
        },
        SwapState::StarknetLocked {
            swap_id: "test2".to_string(),
            contract_address: "0xabc".to_string(),
            lock_until: 9999999999,
            expected_monero_amount: 1_000_000_000,
            hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
            monero_restore_height: Some(1000),
        },
        SwapState::XmrSent {
            swap_id: "test3".to_string(),
            contract_address: "0xabc".to_string(),
            lock_until: 9999999999,
            monero_txid: "tx123".to_string(),
            monero_amount: 1000000,
        },
        SwapState::XmrConfirmed {
            swap_id: "test4".to_string(),
            contract_address: "0xabc".to_string(),
            lock_until: 9999999999,
            monero_txid: "tx123".to_string(),
        },
        SwapState::SecretRevealed {
            swap_id: "test5".to_string(),
            contract_address: "0xabc".to_string(),
            reveal_timestamp: 1234567890,
            monero_restore_height: Some(1000),
            partial_spend_key: Some([0u8; 32]),
            claim_destination: Some("5A1...".to_string()),
        },
        SwapState::Completed {
            swap_id: "test6".to_string(),
            starknet_tx: "0xtx123".to_string(),
            monero_txid: "monero_tx_123".to_string(),
        },
        SwapState::Refunded {
            swap_id: "test7".to_string(),
            reason: "Timeout".to_string(),
            refund_tx: None,
        },
    ];

    for state in states {
        let json = serde_json::to_string(&state).unwrap();
        let parsed: SwapState = serde_json::from_str(&json).unwrap();
        assert_eq!(state, parsed);
    }
}

#[test]
fn test_db_load_nonexistent() {
    let tmp = tempfile::tempdir().unwrap();
    let db = JsonFileDb::new(tmp.path()).unwrap();
    let result = db.load("nonexistent").unwrap();
    assert!(result.is_none());
}

