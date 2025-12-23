//! TDD Tests for Race Condition Detection
//! Detects if secret revealed before Monero tx confirms
//! 
//! P0.3: Critical security requirement from final auditor assessment

use xmr_secret_gen::swap::race_monitor::{
    SecretRevealStatus, RaceConditionMonitor, MockChainState,
};

#[tokio::test]
async fn test_normal_flow_no_race() {
    let mut state = MockChainState::new();
    
    // Monero confirms BEFORE secret revealed
    state.set_monero_confirmations(10);
    state.set_secret_revealed(Some([0x12; 32]));
    
    let monitor = RaceConditionMonitor::new(state);
    let result = monitor.check().await.unwrap();
    
    assert!(matches!(result, SecretRevealStatus::BothComplete));
}

#[tokio::test]
async fn test_race_detected_secret_before_confirm() {
    let mut state = MockChainState::new();
    
    // Secret revealed but Monero has 0 confirmations (RACE!)
    state.set_secret_revealed(Some([0x12; 32]));
    state.set_monero_confirmations(0);
    
    let monitor = RaceConditionMonitor::new(state);
    let result = monitor.check().await.unwrap();
    
    assert!(matches!(result, SecretRevealStatus::RaceDetected { .. }));
}

#[tokio::test]
async fn test_race_detected_secret_before_sufficient_confirmations() {
    let mut state = MockChainState::new();
    
    // Secret revealed but only 5 confirmations (need 10)
    state.set_secret_revealed(Some([0x12; 32]));
    state.set_monero_confirmations(5);
    
    let monitor = RaceConditionMonitor::new(state);
    let result = monitor.check().await.unwrap();
    
    assert!(matches!(result, SecretRevealStatus::RaceDetected { .. }));
}

#[tokio::test]
async fn test_timeout_no_secret() {
    let mut state = MockChainState::new();
    
    // Monero confirms but no secret revealed (timeout)
    state.set_monero_confirmations(10);
    state.set_secret_revealed(None);
    state.set_blocks_elapsed(100); // Past timeout (default 50)
    
    let monitor = RaceConditionMonitor::new(state);
    let result = monitor.check().await;
    
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("Timeout"));
}

#[tokio::test]
async fn test_pending_state() {
    let mut state = MockChainState::new();
    
    // Neither condition met yet
    state.set_monero_confirmations(5);
    state.set_secret_revealed(None);
    
    let monitor = RaceConditionMonitor::new(state);
    let result = monitor.check().await.unwrap();
    
    assert!(matches!(result, SecretRevealStatus::Pending));
}

#[tokio::test]
async fn test_protocol_violation_monero_confirmed_no_secret() {
    let mut state = MockChainState::new();
    
    // Monero confirmed but no secret (protocol violation)
    state.set_monero_confirmations(10);
    state.set_secret_revealed(None);
    state.set_blocks_elapsed(10); // Not timed out yet
    
    let monitor = RaceConditionMonitor::new(state);
    let result = monitor.check().await;
    
    assert!(result.is_err());
    assert!(result.unwrap_err().to_string().contains("Protocol violation"));
}

#[tokio::test]
async fn test_custom_parameters() {
    let mut state = MockChainState::new();
    
    state.set_monero_confirmations(5);
    state.set_secret_revealed(Some([0x12; 32]));
    
    // Custom: require 3 confirmations, timeout 20 blocks
    let monitor = RaceConditionMonitor::with_params(state, 3, 20);
    let result = monitor.check().await.unwrap();
    
    // Should pass with 5 confirmations (>= 3)
    assert!(matches!(result, SecretRevealStatus::BothComplete));
}

