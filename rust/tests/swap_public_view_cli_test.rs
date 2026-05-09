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
            "starknet_receive_mode": "privacy_open_note"
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
    assert!(!stdout.contains("partial_spend_key"));
    assert!(!stdout.contains("claim_destination"));
    assert!(!stdout.contains("42424242"));
}
