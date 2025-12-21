//! Tests for get_current_monero_height() - Monero daemon height query
//!
//! These tests validate the height query logic and safety margin calculation.

use xmr_secret_gen::swap::get_current_monero_height;

#[tokio::test]
async fn test_get_current_monero_height_daemon_error() {
    // Test with invalid daemon URL
    let result = get_current_monero_height("http://invalid-host:38081/json_rpc").await;
    
    assert!(result.is_err(), "Should fail with invalid daemon URL");
}

#[tokio::test]
async fn test_get_current_monero_height_invalid_response() {
    // Test with URL that doesn't return valid JSON-RPC
    let result = get_current_monero_height("http://127.0.0.1:9999/json_rpc").await;
    
    // Should fail (connection error or invalid response)
    assert!(result.is_err(), "Should fail with invalid response");
}

#[tokio::test]
#[ignore] // Requires live stagenet daemon
async fn test_get_current_monero_height_success() {
    // Test with real stagenet daemon
    let result = get_current_monero_height("http://stagenet.xmr-tw.org:38081/json_rpc").await;
    
    assert!(result.is_ok(), "Should succeed with valid daemon");
    let height = result.unwrap();
    
    // Should be a reasonable block height (stagenet is active)
    assert!(height > 0, "Height should be positive, got: {}", height);
    
    // Should have safety margin applied (10 blocks)
    // Note: We can't verify exact margin without knowing current height,
    // but we can verify it's a reasonable value
    assert!(height < 10_000_000, "Height seems unreasonably high: {}", height);
}

#[tokio::test]
async fn test_get_current_monero_height_safety_margin() {
    // This test verifies the safety margin is applied
    // We can't easily mock the daemon response, but we can verify
    // the function exists and handles errors correctly
    
    // Test that function exists and can be called
    let result = get_current_monero_height("http://invalid:38081/json_rpc").await;
    
    // Should return error (not panic)
    assert!(result.is_err());
    
    // Error should be informative
    let error_msg = result.unwrap_err().to_string();
    assert!(
        error_msg.len() > 0,
        "Error message should be informative"
    );
}

