//! Race Condition Monitoring for Atomic Swaps
//! 
//! SECURITY: Detects if Starknet secret is revealed before Monero confirms
//! 
//! P0.3: Critical security requirement from final auditor assessment

use anyhow::{bail, Result};
use tracing::warn;

#[derive(Debug, Clone, PartialEq)]
pub enum SecretRevealStatus {
    /// Both Monero confirmed and secret revealed — normal completion
    BothComplete,
    /// Secret revealed but Monero not confirmed — RACE DETECTED
    RaceDetected { secret: [u8; 32] },
    /// Still waiting
    Pending,
}

/// Chain state for monitoring (implement with real RPC in production)
pub trait ChainState: Send + Sync {
    fn get_monero_confirmations(&self) -> u64;
    fn get_revealed_secret(&self) -> Option<[u8; 32]>;
    fn get_blocks_elapsed(&self) -> u64;
}

pub struct RaceConditionMonitor<S: ChainState> {
    state: S,
    required_confirmations: u64,
    timeout_blocks: u64,
}

impl<S: ChainState> RaceConditionMonitor<S> {
    pub fn new(state: S) -> Self {
        Self {
            state,
            required_confirmations: 10,
            timeout_blocks: 50,
        }
    }
    
    pub fn with_params(state: S, confirmations: u64, timeout: u64) -> Self {
        Self {
            state,
            required_confirmations: confirmations,
            timeout_blocks: timeout,
        }
    }
    
    pub async fn check(&self) -> Result<SecretRevealStatus> {
        let confirmations = self.state.get_monero_confirmations();
        let secret_opt = self.state.get_revealed_secret();
        let elapsed = self.state.get_blocks_elapsed();
        
        // Check timeout first
        if elapsed > self.timeout_blocks && secret_opt.is_none() {
            bail!("Timeout: no secret revealed within {} blocks", self.timeout_blocks);
        }
        
        match (secret_opt, confirmations >= self.required_confirmations) {
            // Normal completion
            (Some(_), true) => Ok(SecretRevealStatus::BothComplete),
            
            // RACE CONDITION: secret revealed but Monero not confirmed
            (Some(secret), false) => {
                if confirmations == 0 {
                    warn!(
                        "RACE DETECTED: Secret revealed before Monero tx in mempool"
                    );
                }
                Ok(SecretRevealStatus::RaceDetected { secret })
            }
            
            // Protocol violation: Monero confirmed without secret
            (None, true) => {
                bail!("Protocol violation: Monero confirmed but no secret revealed")
            }
            
            // Still waiting
            (None, false) => Ok(SecretRevealStatus::Pending),
        }
    }
}

// Mock implementation for testing
// Made public (not cfg(test)) so tests in tests/ directory can use it
pub struct MockChainState {
    confirmations: u64,
    secret: Option<[u8; 32]>,
    blocks_elapsed: u64,
}

impl MockChainState {
    pub fn new() -> Self {
        Self {
            confirmations: 0,
            secret: None,
            blocks_elapsed: 0,
        }
    }
    
    pub fn set_monero_confirmations(&mut self, n: u64) {
        self.confirmations = n;
    }
    
    pub fn set_secret_revealed(&mut self, s: Option<[u8; 32]>) {
        self.secret = s;
    }
    
    pub fn set_blocks_elapsed(&mut self, n: u64) {
        self.blocks_elapsed = n;
    }
}

impl ChainState for MockChainState {
    fn get_monero_confirmations(&self) -> u64 { self.confirmations }
    fn get_revealed_secret(&self) -> Option<[u8; 32]> { self.secret }
    fn get_blocks_elapsed(&self) -> u64 { self.blocks_elapsed }
}

