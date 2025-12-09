use anyhow::Result;
use starknet_core::types::{BlockId, BlockTag, EventFilter, Felt};
use starknet_core::utils::starknet_keccak;
use starknet_providers::{Provider, SequencerGatewayProvider};
use tokio::sync::mpsc;
use tracing::{info, warn, error};
use lazy_static::lazy_static;

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
lazy_static! {
    /// Selector for SecretRevealed(revealer, secret_hash, claimable_after)
    pub static ref SECRET_REVEALED_SELECTOR: Felt = 
        starknet_keccak(b"SecretRevealed");
    
    /// Selector for TokensClaimed(claimer, amount, reveal_timestamp, claim_timestamp)
    pub static ref TOKENS_CLAIMED_SELECTOR: Felt = 
        starknet_keccak(b"TokensClaimed");
    
    /// Selector for Unlocked(unlocker, secret_hash) - backward compatibility
    pub static ref UNLOCKED_SELECTOR: Felt = 
        starknet_keccak(b"Unlocked");
}

impl StarknetListener {
    pub fn new(
        rpc_url: &str,
        watched_contracts: Vec<Felt>,
        event_tx: mpsc::Sender<SwapEvent>,
    ) -> Result<Self> {
        // Use custom RPC URL if provided, otherwise default to Sepolia
        let provider = if rpc_url.contains("zan.top") || rpc_url.contains("blastapi") || rpc_url.contains("nethermind") {
            // Custom RPC endpoint
            SequencerGatewayProvider::new(
                starknet_core::chain_id::SEPOLIA,
                url::Url::parse(rpc_url)?,
            )
        } else {
            SequencerGatewayProvider::starknet_alpha_sepolia()
        };
        
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
        
        if selector == *SECRET_REVEALED_SELECTOR {
            // SecretRevealed event structure:
            // Keys: [selector, revealer (indexed)]
            // Data: [secret_hash (u32), claimable_after (u64)]
            let revealer = event.keys.get(1).copied().unwrap_or(Felt::ZERO);
            
            // Parse data array
            // secret_hash is u32, stored as Felt (low 32 bits)
            let secret_hash = event.data.get(0)
                .map(|f| {
                    // Felt can be converted to u64, then truncated to u32
                    // Use try_into or mask to get low 32 bits
                    let val = f.to_bytes_be();
                    if val.len() >= 4 {
                        u32::from_be_bytes([
                            val[val.len() - 4],
                            val[val.len() - 3],
                            val[val.len() - 2],
                            val[val.len() - 1],
                        ])
                    } else {
                        0
                    }
                })
                .unwrap_or(0);
            
            // claimable_after is u64, stored as Felt
            let claimable_after = event.data.get(1)
                .map(|f| {
                    let val = f.to_bytes_be();
                    if val.len() >= 8 {
                        u64::from_be_bytes([
                            val[val.len() - 8], val[val.len() - 7],
                            val[val.len() - 6], val[val.len() - 5],
                            val[val.len() - 4], val[val.len() - 3],
                            val[val.len() - 2], val[val.len() - 1],
                        ])
                    } else {
                        0
                    }
                })
                .unwrap_or(0);
            
            let evt = SecretRevealedEvent {
                contract_address: event.from_address,
                revealer,
                secret_hash,
                claimable_after,
                block_number,
                transaction_hash: event.transaction_hash,
            };
            
            info!("SecretRevealed event detected: contract {:x}, claimable after {}", 
                evt.contract_address, evt.claimable_after);
            
            self.event_tx.send(SwapEvent::SecretRevealed(evt)).await?;
            
        } else if selector == *TOKENS_CLAIMED_SELECTOR {
            // TokensClaimed event structure:
            // Keys: [selector, claimer (indexed)]
            // Data: [amount (u256 low, u256 high), reveal_timestamp (u64), claim_timestamp (u64)]
            let claimer = event.keys.get(1).copied().unwrap_or(Felt::ZERO);
            
            // Parse amount (u256 = 2 Felts: low, high)
            // For simplicity, we'll parse amount_low as u128
            let amount_low = event.data.get(0)
                .map(|f| {
                    let val = f.to_bytes_be();
                    if val.len() >= 16 {
                        u128::from_be_bytes([
                            val[val.len() - 16], val[val.len() - 15],
                            val[val.len() - 14], val[val.len() - 13],
                            val[val.len() - 12], val[val.len() - 11],
                            val[val.len() - 10], val[val.len() - 9],
                            val[val.len() - 8], val[val.len() - 7],
                            val[val.len() - 6], val[val.len() - 5],
                            val[val.len() - 4], val[val.len() - 3],
                            val[val.len() - 2], val[val.len() - 1],
                        ])
                    } else {
                        0
                    }
                })
                .unwrap_or(0);
            
            let reveal_timestamp = event.data.get(2)
                .map(|f| {
                    let val = f.to_bytes_be();
                    if val.len() >= 8 {
                        u64::from_be_bytes([
                            val[val.len() - 8], val[val.len() - 7],
                            val[val.len() - 6], val[val.len() - 5],
                            val[val.len() - 4], val[val.len() - 3],
                            val[val.len() - 2], val[val.len() - 1],
                        ])
                    } else {
                        0
                    }
                })
                .unwrap_or(0);
            
            let claim_timestamp = event.data.get(3)
                .map(|f| {
                    let val = f.to_bytes_be();
                    if val.len() >= 8 {
                        u64::from_be_bytes([
                            val[val.len() - 8], val[val.len() - 7],
                            val[val.len() - 6], val[val.len() - 5],
                            val[val.len() - 4], val[val.len() - 3],
                            val[val.len() - 2], val[val.len() - 1],
                        ])
                    } else {
                        0
                    }
                })
                .unwrap_or(0);
            
            let evt = TokensClaimedEvent {
                contract_address: event.from_address,
                claimer,
                amount: amount_low,
                reveal_timestamp,
                claim_timestamp,
            };
            
            info!("TokensClaimed event detected: contract {:x}, amount {}", 
                evt.contract_address, evt.amount);
            
            self.event_tx.send(SwapEvent::TokensClaimed(evt)).await?;
        }
        
        Ok(())
    }
}

