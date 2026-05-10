use serde_json::json;

#[test]
fn swap_public_view_cli_outputs_sanitized_frontend_json() {
    let tmp = tempfile::tempdir().unwrap();
    let terms_path = tmp.path().join("terms.json");
    let state_path = tmp.path().join("state.json");

    std::fs::write(
        &terms_path,
        serde_json::to_vec_pretty(&json!({
            "swap_id": "swap-1",
            "direction": "xmr_to_starknet",
            "monero_network": "stagenet",
            "monero_amount_piconero": 5000000000u64,
            "starknet_amount": "40000000000000000000",
            "starknet_token": "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
            "lock_duration_secs": 10800u64,
            "monero_confirmations": 10u64,
            "starknet_receive_mode": "privacy_open_note",
            "starknet_privacy_settlement": {
                "privacy_pool_address": "0x40337b1af3c663e86e333bab5a4b28da8d4652a15a69beee2b677776ffe812a",
                "privacy_helper_address": "0x1eabf8c477f15519b24e0f57cc74657a6cf863d10027dab9b411ce73d784d8d",
                "open_note_id": "0x1234",
                "open_note_token": "0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d",
                "open_note_amount": "40000000000000000000"
            }
        }))
        .unwrap(),
    )
    .unwrap();
    std::fs::write(
        &state_path,
        serde_json::to_vec_pretty(&json!({
            "state": "secret_revealed",
            "swap_id": "swap-1",
            "contract_address": "0xabc",
            "reveal_timestamp": 1000u64,
            "monero_txid": "xmr-tx",
            "monero_amount": 5000000000u64,
            "monero_restore_height": 2000000u64,
            "partial_spend_key": [66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66, 66],
            "claim_destination": "54..."
        }))
        .unwrap(),
    )
    .unwrap();

    let output = assert_cmd::cargo::cargo_bin_cmd!("swap_public_view")
        .args([
            "--terms-json",
            terms_path.to_str().unwrap(),
            "--state-json",
            state_path.to_str().unwrap(),
            "--now",
            "8200",
        ])
        .assert()
        .success()
        .get_output()
        .stdout
        .clone();
    let stdout = String::from_utf8(output).unwrap();
    let view: serde_json::Value = serde_json::from_str(&stdout).unwrap();

    assert_eq!(view["next_action"], "claim_starknet_privacy_note");
    assert_eq!(view["starknet_claimable_after"], 8200);
    assert_eq!(
        view["starknet_privacy_settlement"]["helper_calldata"][0],
        "0xabc"
    );
    assert_eq!(
        view["starknet_privacy_settlement"]["helper_calldata"][1],
        "0x1234"
    );
    assert!(!stdout.contains("partial_spend_key"));
    assert!(!stdout.contains("claim_destination"));
    assert!(!stdout.contains("42424242"));
}
