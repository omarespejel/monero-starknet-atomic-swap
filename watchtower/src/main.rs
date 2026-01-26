use anyhow::Result;
use tokio::sync::mpsc;
use tracing::{info, Level};
use tracing_subscriber::FmtSubscriber;

mod alerts;
mod starknet;
mod monero;
mod relayer;
mod registry;
mod health;
mod types;

use starknet::listener::{StarknetListener, SwapEvent};
use alerts::notifier::Notifier;
use types::{Alert, AlertLevel};
use monero::watcher::monitor_monero_tx;
use relayer::start_relayer_pool;
use registry::SwapRegistry;

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
        .unwrap_or_else(|_| "http://localhost:18081/json_rpc".to_string());

    // Swap registry (persistent)
    let registry_path = std::env::var("SWAP_REGISTRY_PATH")
        .unwrap_or_else(|_| "watchtower_swaps.json".to_string());
    let registry = std::sync::Arc::new(tokio::sync::RwLock::new(
        SwapRegistry::load(registry_path.into())?,
    ));

    // Health endpoint
    let health_addr = std::env::var("HEALTH_ADDR")
        .unwrap_or_else(|_| "127.0.0.1:8080".to_string());
    let _health_handle = health::start_health_server(&health_addr, registry.clone()).await?;

    // Optional: start relayer pool (RPC-based reveal_secret)
    let _relayer_handles = start_relayer_pool(&monero_daemon_url, Some(registry.clone()))?;

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
    let watched_contracts: Vec<String> = watched_contracts_str
        .split(',')
        .filter_map(|s| {
            let s = s.trim();
            if s.is_empty() {
                None
            } else {
                // Normalize hex address (with 0x prefix)
                let hex = s.strip_prefix("0x").unwrap_or(s);
                Some(format!("0x{}", hex))
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
                let contract_address = e.contract_address.clone();
                info!(
                    "Secret revealed for contract {}, claimable after {}",
                    contract_address, e.claimable_after
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
                    contract_address: contract_address.clone(),
                    timestamp: now,
                }).await?;

                // Schedule warning 30 min before grace period expires
                let warning_time = e.claimable_after.saturating_sub(1800); // 30 min = 1800 sec
                let warning_delay = warning_time.saturating_sub(now);
                
                if warning_delay > 0 && warning_delay < 86400 { // Only schedule if < 24 hours
                    let notifier_clone = notifier.clone();
                    let contract = contract_address.clone();
                    
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
                                 Contract: {}",
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
                let contract_hex = contract_address.trim_start_matches("0x");
                let monero_info = std::env::var(format!("MONERO_TXID_{}", contract_hex))
                    .ok()
                    .and_then(|value| {
                        let parts: Vec<&str> = value.split(':').collect();
                        if parts.len() == 2 {
                            parts[1]
                                .parse::<u64>()
                                .ok()
                                .map(|height| (parts[0].to_string(), height))
                        } else {
                            None
                        }
                    });

                if let Some((txid, original_height)) = monero_info.clone() {
                    let swap_id = format!("swap_{}", contract_hex);
                    let daemon_url = monero_daemon_url.clone();
                    let swap_id_spawn = swap_id.clone();
                    let txid_spawn = txid.clone();

                    tokio::spawn(async move {
                        if let Err(e) = monitor_monero_tx(
                            &swap_id_spawn,
                            &txid_spawn,
                            original_height,
                            &daemon_url,
                        ).await {
                            tracing::error!(
                                "[{}] Monero reorg monitoring failed: {}",
                                swap_id_spawn, e
                            );
                        }
                    });

                    info!(
                        "[{}] Started Monero reorg monitoring for TX {}",
                        swap_id, txid
                    );
                }

                // Persist registry update
                {
                    let mut registry = registry.write().await;
                    registry.record_secret_revealed(&e, monero_info);
                    let _ = registry.save();
                }
            }
            SwapEvent::TokensClaimed(e) => {
                info!(
                    "Tokens claimed for contract {}",
                    e.contract_address
                );
                {
                    let mut registry = registry.write().await;
                    registry.record_tokens_claimed(&e);
                    let _ = registry.save();
                }
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

