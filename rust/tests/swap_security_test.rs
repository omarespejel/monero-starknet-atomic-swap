//! Security-focused tests for swap state machine.
//! These tests verify the contract is resistant to common attack vectors.

use anyhow::Result;
use async_trait::async_trait;
use mockall::mock;
use std::sync::atomic::{AtomicU64, Ordering};
use tempfile::tempdir;

use xmr_secret_gen::monero::MoneroWalletClient;
use xmr_secret_gen::monero_wallet::types::TransferInfo;
use xmr_secret_gen::swap::{
    resume_with_xmr_txid, step, JsonFileDb, StarknetClient, SwapDb, SwapState, GRACE_PERIOD_SECS,
};

// === In-Memory DB for Tests ===

struct TestDb {
    states: std::sync::Mutex<std::collections::HashMap<String, SwapState>>,
}

impl TestDb {
    fn new() -> Self {
        Self {
            states: std::sync::Mutex::new(std::collections::HashMap::new()),
        }
    }
}

impl SwapDb for TestDb {
    fn save(&self, state: &SwapState) -> Result<()> {
        self.states
            .lock()
            .unwrap()
            .insert(state.swap_id().to_string(), state.clone());
        Ok(())
    }

    fn load(&self, swap_id: &str) -> Result<Option<SwapState>> {
        Ok(self.states.lock().unwrap().get(swap_id).cloned())
    }
}

// === Mock Starknet Client ===

mock! {
    pub Starknet {}

    #[async_trait]
    impl StarknetClient for Starknet {
        async fn deploy_and_deposit(
            &self,
            hashlock: [u32; 8],
            lock_duration_secs: u64,
            amount: u128,
        ) -> Result<(String, u64)>;
        async fn reveal_secret(&self, contract: &str, secret: &[u8; 32]) -> Result<String>;
        async fn claim_tokens(&self, contract: &str) -> Result<String>;
        async fn refund(&self, contract: &str) -> Result<String>;
        async fn get_block_timestamp(&self) -> Result<u64>;
    }
}

// === Mock Monero Client ===

mock! {
    pub Monero {}

    #[async_trait]
    impl MoneroWalletClient for Monero {
        async fn get_transfer_by_txid(&self, txid: &str) -> Result<TransferInfo>;
    }
}

// === Security Tests ===

#[tokio::test]
async fn test_timeout_triggers_refund_from_starknet_locked() {
    let dir = tempdir().unwrap();
    let db = JsonFileDb::new(dir.path()).unwrap();

    let mut mock_starknet = MockStarknet::new();
    // Return timestamp AFTER lock_until (timeout expired)
    mock_starknet
        .expect_get_block_timestamp()
        .returning(|| Ok(2000)); // lock_until was 1000
    mock_starknet
        .expect_refund()
        .times(1)
        .returning(|_| Ok("0xrefund_tx".to_string()));

    let state = SwapState::StarknetLocked {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        lock_until: 1000, // Expired!
        expected_monero_amount: 1_000_000_000,
        hashlock: [0u32; 8],
        monero_restore_height: Some(1000),
    };

    let mut mock_monero = MockMonero::new();
    // Should not be called since we timeout before checking XMR
    mock_monero.expect_get_transfer_by_txid().times(0);

    let secret = [0u8; 32];

    let result = step(&state, &db, &mock_monero, &mock_starknet, &secret)
        .await
        .unwrap();

    // Should transition to Refunded, not continue normal flow
    match result.unwrap() {
        SwapState::Refunded { reason, .. } => {
            assert!(reason.contains("Timeout"));
        }
        _ => panic!("Expected Refunded state after timeout"),
    }
}

#[tokio::test]
async fn test_cannot_reveal_after_timeout() {
    // Even if in XmrConfirmed, timeout should trigger refund
    let dir = tempdir().unwrap();
    let db = JsonFileDb::new(dir.path()).unwrap();

    let mut mock_starknet = MockStarknet::new();
    mock_starknet
        .expect_get_block_timestamp()
        .returning(|| Ok(5000)); // Way past lock_until
    mock_starknet
        .expect_refund()
        .times(1)
        .returning(|_| Ok("0xrefund".to_string()));
    // Should NOT call reveal_secret
    mock_starknet.expect_reveal_secret().times(0);

    let state = SwapState::XmrConfirmed {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        lock_until: 1000, // Expired
        monero_txid: "abc".to_string(),
        monero_amount: Some(1_000_000_000),
        monero_restore_height: Some(1000),
    };

    let mut mock_monero = MockMonero::new();
    mock_monero.expect_get_transfer_by_txid().times(0);

    let secret = [0u8; 32];

    let result = step(&state, &db, &mock_monero, &mock_starknet, &secret)
        .await
        .unwrap();

    // Should NOT reveal secret - should refund instead
    assert!(matches!(result.unwrap(), SwapState::Refunded { .. }));
}

#[tokio::test]
async fn test_claim_before_grace_period_fails() {
    // Security: Cannot claim tokens before grace period expires
    let dir = tempdir().unwrap();
    let db = JsonFileDb::new(dir.path()).unwrap();

    let reveal_timestamp = 1000;
    let grace_period_end = reveal_timestamp + GRACE_PERIOD_SECS;

    let mut mock_starknet = MockStarknet::new();
    // Current time is BEFORE grace period ends
    mock_starknet
        .expect_get_block_timestamp()
        .returning(move || Ok(reveal_timestamp + 100)); // Only 100 seconds passed
                                                        // Should NOT call claim_tokens (grace period not expired)
    mock_starknet.expect_claim_tokens().times(0);

    let state = SwapState::SecretRevealed {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        reveal_timestamp,
        monero_txid: Some("abc".to_string()),
        monero_amount: Some(1_000_000_000),
        monero_restore_height: Some(1000),
        partial_spend_key: None,
        claim_destination: None,
    };

    let mut mock_monero = MockMonero::new();
    mock_monero.expect_get_transfer_by_txid().times(0);

    let secret = [0u8; 32];

    let result = step(&state, &db, &mock_monero, &mock_starknet, &secret)
        .await
        .unwrap();

    // Should return None (waiting for grace period)
    assert!(result.is_none());
}

#[tokio::test]
async fn test_claim_after_grace_period_succeeds() {
    // Security: Can claim tokens after grace period expires
    let dir = tempdir().unwrap();
    let db = JsonFileDb::new(dir.path()).unwrap();

    let reveal_timestamp = 1000;
    let grace_period_end = reveal_timestamp + GRACE_PERIOD_SECS;

    let mut mock_starknet = MockStarknet::new();
    // Current time is AFTER grace period ends
    mock_starknet
        .expect_get_block_timestamp()
        .returning(move || Ok(grace_period_end + 100)); // Grace period expired
    mock_starknet
        .expect_claim_tokens()
        .times(1)
        .returning(|_| Ok("0xclaim_tx".to_string()));

    let state = SwapState::SecretRevealed {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        reveal_timestamp,
        monero_txid: Some("abc".to_string()),
        monero_amount: Some(1_000_000_000),
        monero_restore_height: Some(1000),
        partial_spend_key: None,
        claim_destination: None,
    };

    let mut mock_monero = MockMonero::new();
    mock_monero.expect_get_transfer_by_txid().times(0);

    let secret = [0u8; 32];

    let result = step(&state, &db, &mock_monero, &mock_starknet, &secret)
        .await
        .unwrap();

    // Should transition to Completed
    match result.unwrap() {
        SwapState::Completed { .. } => {}
        _ => panic!("Expected Completed state after grace period"),
    }
}

#[tokio::test]
async fn test_refund_before_timeout_fails() {
    // Security: Cannot refund before lock_until expires
    let dir = tempdir().unwrap();
    let db = JsonFileDb::new(dir.path()).unwrap();

    let lock_until = 10000;

    let mut mock_starknet = MockStarknet::new();
    // Current time is BEFORE lock_until
    mock_starknet
        .expect_get_block_timestamp()
        .returning(|| Ok(5000)); // Before lock_until
                                 // Should NOT call refund
    mock_starknet.expect_refund().times(0);

    let state = SwapState::StarknetLocked {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        lock_until,
        expected_monero_amount: 1_000_000_000,
        hashlock: [0u32; 8],
        monero_restore_height: Some(1000),
    };

    let mut mock_monero = MockMonero::new();
    mock_monero.expect_get_transfer_by_txid().times(0);

    let secret = [0u8; 32];

    let result = step(&state, &db, &mock_monero, &mock_starknet, &secret)
        .await
        .unwrap();

    // Should return None (waiting, no transition)
    assert!(result.is_none());
}

#[tokio::test]
async fn test_terminal_states_are_final() {
    // Invariant: Completed and Refunded states cannot transition
    let dir = tempdir().unwrap();
    let db = JsonFileDb::new(dir.path()).unwrap();

    let mut mock_starknet = MockStarknet::new();
    // Should not be called for terminal states
    mock_starknet.expect_get_block_timestamp().times(0);
    mock_starknet.expect_deploy_and_deposit().times(0);
    mock_starknet.expect_reveal_secret().times(0);
    mock_starknet.expect_claim_tokens().times(0);
    mock_starknet.expect_refund().times(0);

    let mut mock_monero = MockMonero::new();
    mock_monero.expect_get_transfer_by_txid().times(0);

    let secret = [0u8; 32];

    // Test Completed state
    let completed_state = SwapState::Completed {
        swap_id: "test1".to_string(),
        starknet_tx: "0xtx1".to_string(),
        monero_txid: "abc".to_string(),
    };

    let result = step(&completed_state, &db, &mock_monero, &mock_starknet, &secret)
        .await
        .unwrap();

    // Should return None (no transition from terminal)
    assert!(result.is_none());

    // Test Refunded state
    let refunded_state = SwapState::Refunded {
        swap_id: "test2".to_string(),
        reason: "Timeout".to_string(),
        refund_tx: Some("0xrefund".to_string()),
    };

    let result = step(&refunded_state, &db, &mock_monero, &mock_starknet, &secret)
        .await
        .unwrap();

    // Should return None (no transition from terminal)
    assert!(result.is_none());
}

#[tokio::test]
async fn test_state_machine_cannot_skip_states() {
    // Invariant: Cannot jump from Created -> XmrConfirmed
    // Must go through StarknetLocked -> XmrSent -> XmrConfirmed
    let dir = tempdir().unwrap();
    let db = JsonFileDb::new(dir.path()).unwrap();

    let mut mock_starknet = MockStarknet::new();
    mock_starknet
        .expect_get_block_timestamp()
        .returning(|| Ok(1000));

    let mut mock_monero = MockMonero::new();
    // Should not be called - we're in Created state, should deploy first
    mock_monero.expect_get_transfer_by_txid().times(0);

    let state = SwapState::Created {
        swap_id: "test".to_string(),
        lock_duration_secs: 3600,
        amount: 1000,
        expected_monero_amount: 1_000_000_000,
        hashlock: [0u32; 8],
        monero_restore_height: Some(1000),
    };

    let secret = [0u8; 32];

    // From Created, should transition to StarknetLocked (deploy contract)
    mock_starknet
        .expect_deploy_and_deposit()
        .times(1)
        .returning(|_, _, _| Ok(("0xcontract".to_string(), 4600)));

    let result = step(&state, &db, &mock_monero, &mock_starknet, &secret)
        .await
        .unwrap();

    // Should transition to StarknetLocked, not skip to XmrConfirmed
    match result.unwrap() {
        SwapState::StarknetLocked { .. } => {}
        _ => panic!("Expected StarknetLocked state, cannot skip states"),
    }
}

#[test]
fn test_resume_rejects_insufficient_amount() {
    // SECURITY: resume_with_xmr_txid validates amount to prevent fund loss attacks
    let state = SwapState::StarknetLocked {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        lock_until: 9999999,
        expected_monero_amount: 10_000_000_000, // 10 XMR in piconero
        hashlock: [0u32; 8],
        monero_restore_height: Some(1000),
    };

    let actual_amount = 1_000_000; // 0.001 XMR (insufficient!)

    // Should reject insufficient amount (expected amount is in state)
    let result = resume_with_xmr_txid(&state, "txid".to_string(), actual_amount);

    assert!(result.is_err());
    let error_msg = result.unwrap_err().to_string();
    assert!(error_msg.contains("amount") || error_msg.contains("less than expected"));
}

#[test]
fn test_resume_accepts_sufficient_amount() {
    // SECURITY: Should accept when amount meets or exceeds expected
    let state = SwapState::StarknetLocked {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        lock_until: 9999999,
        expected_monero_amount: 10_000_000_000, // 10 XMR in piconero
        hashlock: [0u32; 8],
        monero_restore_height: Some(1000),
    };

    let actual_amount = 10_000_000_000; // Exactly 10 XMR (sufficient)

    // Should accept exact amount (expected amount is in state)
    let result = resume_with_xmr_txid(&state, "txid".to_string(), actual_amount);
    assert!(result.is_ok());

    // Should also accept amount greater than expected
    let actual_amount_excess = 11_000_000_000; // 11 XMR (more than expected)
    let result2 = resume_with_xmr_txid(&state, "txid2".to_string(), actual_amount_excess);
    assert!(result2.is_ok());
}

#[tokio::test]
async fn test_timeout_checked_on_every_step() {
    // Security: Timeout must be checked before ANY state transition
    // Not just at specific states
    let dir = tempdir().unwrap();
    let db = JsonFileDb::new(dir.path()).unwrap();

    let lock_until = 1000; // Expired

    let mut mock_starknet = MockStarknet::new();
    // Always return timestamp AFTER lock_until
    mock_starknet
        .expect_get_block_timestamp()
        .returning(|| Ok(2000)); // Expired
    mock_starknet
        .expect_refund()
        .times(1)
        .returning(|_| Ok("0xrefund".to_string()));

    let mut mock_monero = MockMonero::new();
    mock_monero.expect_get_transfer_by_txid().times(0);

    let secret = [0u8; 32];

    // Test from XmrSent state (should check timeout before confirming)
    let state = SwapState::XmrSent {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        lock_until,
        monero_txid: "abc".to_string(),
        monero_amount: 1_000_000_000,
        monero_restore_height: Some(1000),
    };

    let result = step(&state, &db, &mock_monero, &mock_starknet, &secret)
        .await
        .unwrap();

    // Should refund due to timeout, not proceed to XmrConfirmed
    assert!(matches!(result.unwrap(), SwapState::Refunded { .. }));
}

#[test]
fn test_grace_period_constant_matches_cairo() {
    // SECURITY: Grace period constant must match Cairo contract
    // This prevents mismatches that could cause incorrect grace period calculations
    // Cairo contract: const GRACE_PERIOD: u64 = 7200;  // 2 hours (line 109 in lib.cairo)
    // Rust constant: pub const GRACE_PERIOD_SECS: u64 = 7200;

    use xmr_secret_gen::swap::GRACE_PERIOD_SECS;

    const CAIRO_GRACE_PERIOD: u64 = 7200; // From cairo/src/lib.cairo:109

    assert_eq!(
        GRACE_PERIOD_SECS, CAIRO_GRACE_PERIOD,
        "Rust GRACE_PERIOD_SECS ({}) must match Cairo GRACE_PERIOD ({})",
        GRACE_PERIOD_SECS, CAIRO_GRACE_PERIOD
    );

    // Verify it's 2 hours (7200 seconds)
    assert_eq!(
        GRACE_PERIOD_SECS,
        2 * 60 * 60,
        "Grace period should be 2 hours (7200 seconds)"
    );
}

#[tokio::test]
async fn test_double_reveal_attack_prevented() {
    // Attack: Attacker calls reveal_secret twice
    // Expected: State machine should handle gracefully (contract will revert)
    // This test verifies state machine doesn't crash on second reveal attempt

    let dir = tempdir().unwrap();
    let db = JsonFileDb::new(dir.path()).unwrap();

    let reveal_timestamp = 1000;
    let grace_period_end = reveal_timestamp + GRACE_PERIOD_SECS;

    let mut mock_starknet = MockStarknet::new();
    // First call: reveal succeeds
    let reveal_ts = reveal_timestamp;
    mock_starknet
        .expect_get_block_timestamp()
        .returning(move || Ok(reveal_ts));
    mock_starknet
        .expect_reveal_secret()
        .times(1)
        .returning(|_, _| Ok("0xreveal1".to_string()));

    let state = SwapState::XmrConfirmed {
        swap_id: "test".to_string(),
        contract_address: "0x123".to_string(),
        lock_until: 9999999,
        monero_txid: "abc".to_string(),
        monero_amount: Some(1_000_000_000),
        monero_restore_height: Some(1000),
    };

    let mut mock_monero = MockMonero::new();
    mock_monero.expect_get_transfer_by_txid().times(0);

    let secret = [0u8; 32];

    // First reveal
    let result1 = step(&state, &db, &mock_monero, &mock_starknet, &secret)
        .await
        .unwrap();

    // Should transition to SecretRevealed
    let revealed_state = result1.unwrap();
    assert!(matches!(revealed_state, SwapState::SecretRevealed { .. }));

    // Second reveal attempt (from SecretRevealed state)
    // Should NOT call reveal_secret again (already revealed)
    let mut mock_starknet2 = MockStarknet::new();
    let grace_end = grace_period_end;
    mock_starknet2
        .expect_get_block_timestamp()
        .returning(move || Ok(grace_end + 100)); // After grace period
    mock_starknet2.expect_reveal_secret().times(0); // Should not be called
    mock_starknet2
        .expect_claim_tokens()
        .times(1)
        .returning(|_| Ok("0xclaim".to_string()));

    let result2 = step(&revealed_state, &db, &mock_monero, &mock_starknet2, &secret)
        .await
        .unwrap();

    // Should proceed to claim, not reveal again
    assert!(matches!(result2.unwrap(), SwapState::Completed { .. }));
}
