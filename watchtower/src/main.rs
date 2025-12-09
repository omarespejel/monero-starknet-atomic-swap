use anyhow::Result;
use tokio::sync::mpsc;
use tracing::{info, Level};
use tracing_subscriber::FmtSubscriber;

mod alerts;
mod starknet;
mod monero;
mod types;

use starknet::listener::{StarknetListener, SwapEvent};
use alerts::notifier::Notifier;
use types::{Alert, AlertLevel, SwapState};

#[tokio::main]
async fn main() -> Result<()> {
    // Initialize logging
    let subscriber = FmtSubscriber::builder()
        .with_max_level(Level::INFO)
        .finish();
    tracing::subscriber::set_global_default(subscriber)?;

    info!("Starting Atomic Swap Watchtower");

    // Load configuration
    dotenvy::dotenv().ok();
    
    let discord_webhook = std::env::var("DISCORD_WEBHOOK").ok();
    let telegram_token = std::env::var("TELEGRAM_BOT_TOKEN").ok();
    let telegram_chat = std::env::var("TELEGRAM_CHAT_ID").ok();

    // Initialize notifier
    let notifier = Notifier::new(discord_webhook, telegram_token, telegram_chat);

    // Create event channel
    let (event_tx, mut event_rx) = mpsc::channel::<SwapEvent>(100);

    // Initialize Starknet listener
    // Load RPC URL from env or use default (ZAN public endpoint)
    let rpc_url = std::env::var("STARKNET_RPC_URL")
        .unwrap_or_else(|_| "https://api.zan.top/public/starknet-sepolia".to_string());
    
    // Load watched contracts from env (comma-separated)
    let watched_contracts_str = std::env::var("WATCHED_CONTRACTS").unwrap_or_default();
    let watched_contracts: Vec<starknet_core::types::Felt> = watched_contracts_str
        .split(',')
        .filter_map(|s| {
            let s = s.trim();
            if s.is_empty() {
                None
            } else {
                // Parse hex address (with or without 0x prefix)
                let hex = s.strip_prefix("0x").unwrap_or(s);
                // Use Felt::from_hex_str or parse manually
                hex.parse::<starknet_core::types::Felt>().ok()
            }
        })
        .collect();
    
    if watched_contracts.is_empty() {
        info!("No contracts configured for monitoring. Add WATCHED_CONTRACTS to .env");
    } else {
        info!("Monitoring {} contract(s)", watched_contracts.len());
    }
    
    let listener = StarknetListener::new(
        &rpc_url,
        watched_contracts,
        event_tx,
    )?;

    // Spawn listener task
    let listener_handle = tokio::spawn(async move {
        if let Err(e) = listener.run().await {
            tracing::error!("Listener error: {}", e);
        }
    });

    // Process events
    while let Some(event) = event_rx.recv().await {
        match event {
            SwapEvent::SecretRevealed(e) => {
                info!(
                    "Secret revealed for contract {:x}, claimable after {}",
                    e.contract_address, e.claimable_after
                );
                // Calculate time until claimable
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)?
                    .as_secs();
                
                let time_until_claim = e.claimable_after.saturating_sub(now);
                
                notifier.send_alert(&Alert {
                    level: AlertLevel::Info,
                    title: "Secret Revealed - Grace Period Started".to_string(),
                    message: format!(
                        "Secret has been revealed. Tokens claimable in {} minutes.\n\
                         Monitor Monero transaction for confirmation.",
                        time_until_claim / 60
                    ),
                    contract_address: e.contract_address,
                    timestamp: now,
                }).await?;

                // Schedule warning 30 min before grace period expires
                let warning_time = e.claimable_after.saturating_sub(1800); // 30 min = 1800 sec
                let warning_delay = warning_time.saturating_sub(now);
                
                if warning_delay > 0 && warning_delay < 86400 { // Only schedule if < 24 hours
                    let notifier_clone = notifier.clone();
                    let contract = e.contract_address;
                    
                    tokio::spawn(async move {
                        tokio::time::sleep(std::time::Duration::from_secs(warning_delay)).await;
                        
                        let now = std::time::SystemTime::now()
                            .duration_since(std::time::UNIX_EPOCH)
                            .unwrap()
                            .as_secs();
                        
                        notifier_clone.send_alert(&Alert {
                            level: AlertLevel::Warning,
                            title: "Grace Period Expiring Soon".to_string(),
                            message: format!(
                                "Grace period expires in ~30 minutes. Ensure Monero TX is confirmed.\n\
                                 Contract: 0x{:x}",
                                contract
                            ),
                            contract_address: contract,
                            timestamp: now,
                        }).await.ok();
                    });
                }

                // TODO: Start monitoring Monero confirmations
            }
            SwapEvent::TokensClaimed(e) => {
                info!(
                    "Tokens claimed for contract {:x}",
                    e.contract_address
                );
                notifier.send_alert(&Alert {
                    level: AlertLevel::Info,
                    title: "Swap Completed".to_string(),
                    message: format!(
                        "Tokens successfully claimed. Swap complete.\n\
                         Amount: {} tokens",
                        e.amount
                    ),
                    contract_address: e.contract_address,
                    timestamp: e.claim_timestamp,
                }).await?;
            }
        }
    }

    listener_handle.await?;

    Ok(())
}

