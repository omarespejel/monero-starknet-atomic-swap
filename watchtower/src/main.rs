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
    // TODO: Load watched contracts from config
    let watched_contracts = vec![];
    let listener = StarknetListener::new(
        "https://starknet-sepolia.public.blastapi.io",
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

                // TODO: Start monitoring Monero confirmations
                // TODO: Schedule reminder before grace period expires
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

