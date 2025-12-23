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
use monero::watcher::monitor_monero_tx;

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
    
    // Monero daemon URL for reorg detection
    let monero_daemon_url = std::env::var("MONERO_DAEMON_URL")
        .unwrap_or_else(|_| "http://localhost:18081".to_string());

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

                // Start monitoring Monero transaction for reorgs
                // Note: monero_txid and original_height should be provided via:
                // - Environment variable MONERO_TXID_{contract_address}
                // - Or added to SecretRevealedEvent structure
                // For now, we check if MONERO_TXID env var is set (format: "txid:height")
                let contract_hex = format!("{:x}", e.contract_address);
                if let Ok(monero_info) = std::env::var(format!("MONERO_TXID_{}", contract_hex)) {
                    let parts: Vec<&str> = monero_info.split(':').collect();
                    if parts.len() == 2 {
                        if let Ok(original_height) = parts[1].parse::<u64>() {
                            let txid = parts[0].to_string();
                            let swap_id = format!("swap_{:x}", e.contract_address);
                            let daemon_url = monero_daemon_url.clone();
                            
                            tokio::spawn(async move {
                                if let Err(e) = monitor_monero_tx(
                                    &swap_id,
                                    &txid,
                                    original_height,
                                    &daemon_url,
                                ).await {
                                    tracing::error!(
                                        "[{}] Monero reorg monitoring failed: {}",
                                        swap_id, e
                                    );
                                }
                            });
                            
                            info!(
                                "[{}] Started Monero reorg monitoring for TX {}",
                                swap_id, txid
                            );
                        }
                    }
                }
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

