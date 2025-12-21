use anyhow::Result;
use async_trait::async_trait;
use std::sync::atomic::{AtomicU64, Ordering};

use xmr_secret_gen::swap::{SwapState, SwapDb, step, resume_with_xmr_txid, StarknetClient, GRACE_PERIOD_SECS};
use xmr_secret_gen::monero::MoneroWalletClient;
use xmr_secret_gen::monero_wallet::types::TransferInfo;

// === In-Memory DB for Tests ===

struct TestDb {
    states: std::sync::Mutex<std::collections::HashMap<String, SwapState>>,
}

impl TestDb {
    fn new() -> Self {
        Self { states: std::sync::Mutex::new(std::collections::HashMap::new()) }
    }
}

impl SwapDb for TestDb {
    fn save(&self, state: &SwapState) -> Result<()> {
        self.states.lock().unwrap().insert(state.swap_id().to_string(), state.clone());
        Ok(())
    }
    
    fn load(&self, swap_id: &str) -> Result<Option<SwapState>> {
        Ok(self.states.lock().unwrap().get(swap_id).cloned())
    }
}

// === Mock Starknet Client ===

struct MockStarknet {
    timestamp: AtomicU64,
    deploy_result: Result<(String, u64)>,
}

impl MockStarknet {
    fn new(timestamp: u64) -> Self {
        Self {
            timestamp: AtomicU64::new(timestamp),
            deploy_result: Ok(("0xcontract".to_string(), timestamp + 10800)),
        }
    }
    
    fn advance_time(&self, secs: u64) {
        self.timestamp.fetch_add(secs, Ordering::SeqCst);
    }
}

#[async_trait]
impl StarknetClient for MockStarknet {
    async fn deploy_and_deposit(&self, _: [u32; 8], lock_duration: u64, _: u128) -> Result<(String, u64)> {
        let now = self.timestamp.load(Ordering::SeqCst);
        Ok(("0xcontract".to_string(), now + lock_duration))
    }
    
    async fn reveal_secret(&self, _: &str, _: &[u8; 32]) -> Result<String> {
        Ok("0xreveal_tx".to_string())
    }
    
    async fn claim_tokens(&self, _: &str) -> Result<String> {
        Ok("0xclaim_tx".to_string())
    }
    
    async fn refund(&self, _: &str) -> Result<String> {
        Ok("0xrefund_tx".to_string())
    }
    
    async fn get_block_timestamp(&self) -> Result<u64> {
        Ok(self.timestamp.load(Ordering::SeqCst))
    }
}

// === Mock Monero Client ===

struct MockMonero {
    confirmations: u64,
}

#[async_trait]
impl MoneroWalletClient for MockMonero {
    async fn get_transfer_by_txid(&self, txid: &str) -> Result<TransferInfo> {
        Ok(TransferInfo {
            txid: txid.to_string(),
            confirmations: self.confirmations,
            height: 12345,
            amount: 1_000_000_000,
            unlock_time: 0,
        })
    }
}

// === Tests ===

#[tokio::test]
async fn test_step_created_to_starknet_locked() {
    let db = TestDb::new();
    let monero = MockMonero { confirmations: 0 };
    let starknet = MockStarknet::new(1000000);
    let secret = [0x12u8; 32];

    let initial = SwapState::Created {
        swap_id: "test-1".to_string(),
        lock_duration_secs: 10800,
        amount: 1000000000000000000,
        expected_monero_amount: 1_000_000_000, // 1 XMR in piconero
        hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
        monero_restore_height: Some(1000),
    };

    let result = step(&initial, &db, &monero, &starknet, &secret).await.unwrap();
    
    assert!(result.is_some());
    let new_state = result.unwrap();
    assert!(matches!(new_state, SwapState::StarknetLocked { .. }));
    
    // Verify persisted
    let loaded = db.load("test-1").unwrap().unwrap();
    assert!(matches!(loaded, SwapState::StarknetLocked { .. }));
}

#[tokio::test]
async fn test_step_starknet_locked_returns_none() {
    let db = TestDb::new();
    let monero = MockMonero { confirmations: 0 };
    let starknet = MockStarknet::new(1000000);
    let secret = [0x12u8; 32];

    let state = SwapState::StarknetLocked {
        swap_id: "test-2".to_string(),
        contract_address: "0xabc".to_string(),
        lock_until: 1010800,
        expected_monero_amount: 1_000_000_000, // 1 XMR in piconero
        hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
        monero_restore_height: Some(1000),
    };

    // Should return None (waiting for XMR txid)
    let result = step(&state, &db, &monero, &starknet, &secret).await.unwrap();
    assert!(result.is_none());
}

#[tokio::test]
async fn test_resume_with_xmr_txid() {
    let state = SwapState::StarknetLocked {
        swap_id: "test-3".to_string(),
        contract_address: "0xabc".to_string(),
        lock_until: 1010800,
        expected_monero_amount: 1_000_000_000, // 1 XMR in piconero
        hashlock: [1, 2, 3, 4, 5, 6, 7, 8],
        monero_restore_height: Some(1000),
    };

    let new_state = resume_with_xmr_txid(&state, "monero_txid_123".to_string(), 1_000_000_000).unwrap();
    
    assert!(matches!(new_state, SwapState::XmrSent { monero_txid, .. } if monero_txid == "monero_txid_123"));
}

#[tokio::test]
async fn test_step_xmr_sent_to_confirmed() {
    let db = TestDb::new();
    let monero = MockMonero { confirmations: 15 }; // Already confirmed
    let starknet = MockStarknet::new(1000000);
    let secret = [0x12u8; 32];

    let state = SwapState::XmrSent {
        swap_id: "test-4".to_string(),
        contract_address: "0xabc".to_string(),
        lock_until: 1010800,
        monero_txid: "txid123".to_string(),
        monero_amount: 1_000_000_000,
    };

    let result = step(&state, &db, &monero, &starknet, &secret).await.unwrap();
    
    assert!(result.is_some());
    assert!(matches!(result.unwrap(), SwapState::XmrConfirmed { .. }));
}

#[tokio::test]
async fn test_step_xmr_confirmed_to_secret_revealed() {
    let db = TestDb::new();
    let monero = MockMonero { confirmations: 15 };
    let starknet = MockStarknet::new(1000000);
    let secret = [0x12u8; 32];

    let state = SwapState::XmrConfirmed {
        swap_id: "test-5".to_string(),
        contract_address: "0xabc".to_string(),
        lock_until: 1010800,
        monero_txid: "txid123".to_string(),
    };

    let result = step(&state, &db, &monero, &starknet, &secret).await.unwrap();
    
    assert!(result.is_some());
    match result.unwrap() {
        SwapState::SecretRevealed { 
            monero_restore_height: _,
            partial_spend_key: _,
            claim_destination: _,
            .. 
        } => {},
        _ => panic!("Expected SecretRevealed state"),
    }
}

#[tokio::test]
async fn test_step_secret_revealed_waits_for_grace_period() {
    let db = TestDb::new();
    let monero = MockMonero { confirmations: 15 };
    let starknet = MockStarknet::new(1000000);
    let secret = [0x12u8; 32];

    let state = SwapState::SecretRevealed {
        swap_id: "test-6".to_string(),
        contract_address: "0xabc".to_string(),
        reveal_timestamp: 1000000, // Same as current time
        monero_restore_height: Some(1000),
        partial_spend_key: None,
        claim_destination: None,
    };

    // Should return None (still in grace period)
    let result = step(&state, &db, &monero, &starknet, &secret).await.unwrap();
    assert!(result.is_none());
}

#[tokio::test]
async fn test_step_secret_revealed_to_completed() {
    let db = TestDb::new();
    let monero = MockMonero { confirmations: 15 };
    let starknet = MockStarknet::new(1000000 + GRACE_PERIOD_SECS + 1); // Past grace period
    let secret = [0x12u8; 32];

    let state = SwapState::SecretRevealed {
        swap_id: "test-7".to_string(),
        contract_address: "0xabc".to_string(),
        reveal_timestamp: 1000000,
        monero_restore_height: Some(1000),
        partial_spend_key: None,
        claim_destination: None,
    };

    let result = step(&state, &db, &monero, &starknet, &secret).await.unwrap();
    
    assert!(result.is_some());
    assert!(matches!(result.unwrap(), SwapState::Completed { .. }));
}

#[tokio::test]
async fn test_step_timeout_triggers_refund() {
    let db = TestDb::new();
    let monero = MockMonero { confirmations: 0 };
    let starknet = MockStarknet::new(2000000); // Way past lock_until
    let secret = [0x12u8; 32];

    let state = SwapState::XmrSent {
        swap_id: "test-8".to_string(),
        contract_address: "0xabc".to_string(),
        lock_until: 1010800, // Already expired
        monero_txid: "txid123".to_string(),
        monero_amount: 1_000_000_000,
    };

    let result = step(&state, &db, &monero, &starknet, &secret).await.unwrap();
    
    assert!(result.is_some());
    assert!(matches!(result.unwrap(), SwapState::Refunded { .. }));
}

#[tokio::test]
async fn test_step_terminal_state_returns_none() {
    let db = TestDb::new();
    let monero = MockMonero { confirmations: 15 };
    let starknet = MockStarknet::new(1000000);
    let secret = [0x12u8; 32];

    let state = SwapState::Completed {
        swap_id: "test-9".to_string(),
        starknet_tx: "0xtx".to_string(),
        monero_txid: "txid".to_string(),
    };

    let result = step(&state, &db, &monero, &starknet, &secret).await.unwrap();
    assert!(result.is_none());
}

