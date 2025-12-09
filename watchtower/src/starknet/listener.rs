use anyhow::Result;
use starknet_core::types::{BlockId, BlockTag, EventFilter, Felt};
use starknet_providers::{Provider, SequencerGatewayProvider};
use tokio::sync::mpsc;
use tracing::{info, warn, error};

use crate::types::{SecretRevealedEvent, TokensClaimedEvent};

/// Starknet event listener for AtomicLock contracts
pub struct StarknetListener {
    provider: SequencerGatewayProvider,
    /// Contract addresses to monitor
    watched_contracts: Vec<Felt>,
    /// Channel to send events
    event_tx: mpsc::Sender<SwapEvent>,
}

pub enum SwapEvent {
    SecretRevealed(SecretRevealedEvent),
    TokensClaimed(TokensClaimedEvent),
}

// Event selector hashes (keccak256 of event signature)
// These need to be computed from the actual Cairo event signatures
const SECRET_REVEALED_SELECTOR: Felt = Felt::ZERO; // TODO: Compute actual selector
const TOKENS_CLAIMED_SELECTOR: Felt = Felt::ZERO;  // TODO: Compute actual selector

impl StarknetListener {
    pub fn new(
        rpc_url: &str,
        watched_contracts: Vec<Felt>,
        event_tx: mpsc::Sender<SwapEvent>,
    ) -> Result<Self> {
        let provider = SequencerGatewayProvider::starknet_alpha_sepolia();
        
        Ok(Self {
            provider,
            watched_contracts,
            event_tx,
        })
    }

    /// Start listening for events
    pub async fn run(&self) -> Result<()> {
        info!("Starting Starknet event listener");
        
        let mut last_block = self.get_latest_block().await?;
        
        loop {
            // Poll for new blocks
            tokio::time::sleep(tokio::time::Duration::from_secs(10)).await;
            
            let current_block = self.get_latest_block().await?;
            
            if current_block > last_block {
                // Process new blocks
                for block_num in (last_block + 1)..=current_block {
                    if let Err(e) = self.process_block(block_num).await {
                        error!("Failed to process block {}: {}", block_num, e);
                    }
                }
                last_block = current_block;
            }
        }
    }

    async fn get_latest_block(&self) -> Result<u64> {
        let block = self.provider
            .get_block_with_tx_hashes(BlockId::Tag(BlockTag::Latest))
            .await?;
        Ok(block.block_number())
    }

    async fn process_block(&self, block_number: u64) -> Result<()> {
        info!("Processing block {}", block_number);
        
        for contract in &self.watched_contracts {
            let filter = EventFilter {
                from_block: Some(BlockId::Number(block_number)),
                to_block: Some(BlockId::Number(block_number)),
                address: Some(*contract),
                keys: None,
            };
            let events = self.provider
                .get_events(filter, None, 100)
                .await?;
            for event in events.events {
                self.handle_event(event, block_number).await?;
            }
        }
        
        Ok(())
    }

    async fn handle_event(
        &self,
        event: starknet_core::types::EmittedEvent,
        block_number: u64,
    ) -> Result<()> {
        let selector = event.keys.first().copied().unwrap_or(Felt::ZERO);
        
        // TODO: Parse events based on selector
        // This requires knowing the exact event structure from Cairo
        
        if selector == SECRET_REVEALED_SELECTOR {
            info!("SecretRevealed event detected in block {}", block_number);
            // Parse and send event
        } else if selector == TOKENS_CLAIMED_SELECTOR {
            info!("TokensClaimed event detected in block {}", block_number);
            // Parse and send event
        }
        
        Ok(())
    }
}

