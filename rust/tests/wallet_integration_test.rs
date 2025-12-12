//! Production-grade Monero wallet RPC integration tests
//! Based on COMIT Network's 3+ years of mainnet atomic swap experience

mod helpers;

use anyhow::Result;
use helpers::monero_wallet::MoneroWallet;

// Helper: Convert XMR to piconero (atomic units)
// 1 XMR = 10^12 piconero
fn xmr_to_piconero(xmr: f64) -> u64 {
    (xmr * 1_000_000_000_000.0) as u64
}

// Helper: Convert piconero to XMR
fn piconero_to_xmr(piconero: u64) -> f64 {
    piconero as f64 / 1_000_000_000_000.0
}

#[tokio::test]
#[ignore] // Run with: cargo test --test wallet_integration_test -- --ignored
async fn test_wallet_connection_and_balance() -> Result<()> {
    let _ = tracing_subscriber::fmt::try_init(); // Try init, ignore if already initialized

    println!("🔄 Testing Monero wallet-rpc connection...");
    println!("⚠️  Requirements:");
    println!("   1. Run: docker-compose up -d");
    println!("   2. Wait for daemon sync (~30-60 min)");
    println!("   3. Or use: monero-wallet-rpc --stagenet --rpc-bind-port 38088");

    let wallet = MoneroWallet::new(
        "http://localhost:38088/json_rpc".to_string(),
        "http://stagenet.xmr-tw.org:38081".to_string(),
        "atomic-swap-test".to_string(),
    ).await?;

    // Create or open wallet
    match wallet.create_wallet("test123").await {
        Ok(_) => println!("✅ Created new wallet"),
        Err(_) => {
            wallet.open_wallet("test123").await?;
            println!("✅ Opened existing wallet");
        }
    }

    // Get address
    let address = wallet.get_address().await?;
    println!("📍 Stagenet address: {}", address);
    println!("💡 Fund via: https://stagenet-faucet.xmr-tw.org/");

    // Get balance
    let (balance, unlocked) = wallet.get_balance().await?;
    println!("💰 Balance: {:.12} XMR", piconero_to_xmr(balance));
    println!("🔓 Unlocked: {:.12} XMR", piconero_to_xmr(unlocked));

    if balance == 0 {
        println!("⚠️  Wallet has no balance. Fund it to run transaction tests.");
    }

    Ok(())
}

#[tokio::test]
#[ignore]
async fn test_locked_transaction_creation() -> Result<()> {
    let _ = tracing_subscriber::fmt::try_init(); // Try init, ignore if already initialized

    println!("🔐 Testing locked transaction creation...");

    let wallet = MoneroWallet::new(
        "http://localhost:38088/json_rpc".to_string(),
        "http://stagenet.xmr-tw.org:38081".to_string(),
        "atomic-swap-test".to_string(),
    ).await?;

    wallet.open_wallet("test123").await?;

    // Check balance
    let (balance, unlocked) = wallet.get_balance().await?;
    let min_balance = xmr_to_piconero(0.1);
    if unlocked < min_balance {
        println!("⚠️  Insufficient balance. Need at least 0.1 XMR unlocked.");
        println!("   Current: {:.12} XMR unlocked", piconero_to_xmr(unlocked));
        return Ok(());
    }

    // Get current block height for timelock
    let current_height = wallet.get_height().await?;
    let unlock_height = current_height + 10; // Lock for 10 blocks

    println!("📊 Current height: {}", current_height);
    println!("🔒 Will unlock at height: {}", unlock_height);

    // Create dummy destination (send to self for testing)
    let destination = wallet.get_address().await?;
    let amount_piconero = xmr_to_piconero(0.01); // 0.01 XMR test

    println!("💸 Creating locked transaction:");
    println!("   Amount: {:.12} XMR", piconero_to_xmr(amount_piconero));
    println!("   Destination: {}", destination);
    println!("   Unlock time: {} blocks", unlock_height);

    // Create locked transaction (ATOMIC SWAP CORE FUNCTION)
    let result = wallet.transfer_locked(
        &destination,
        amount_piconero,
        unlock_height,
    ).await?;

    println!("✅ Transaction created!");
    println!("   TX Hash: {}", result.tx_hash);
    println!("   TX Key: {}", result.tx_key);
    println!("   Amount: {:.12} XMR", piconero_to_xmr(result.amount));
    println!("   Fee: {:.12} XMR", piconero_to_xmr(result.fee));

    // Wait for 2 confirmations (quick test)
    println!("⏳ Waiting for 2 confirmations...");
    wallet.wait_for_confirmations(&result.tx_hash, 2).await?;
    println!("✅ Transaction confirmed!");

    // Verify transaction details
    let tx_info = wallet.get_transfer_by_txid(&result.tx_hash).await?;
    println!("📊 Transaction info:");
    println!("   Confirmations: {}", tx_info.confirmations);
    println!("   Height: {}", tx_info.height);
    println!("   Unlock time: {}", tx_info.unlock_time);

    assert!(tx_info.confirmations >= 2);
    assert_eq!(tx_info.unlock_time, unlock_height);

    Ok(())
}

#[tokio::test]
#[ignore]
async fn test_ten_confirmation_safety() -> Result<()> {
    let _ = tracing_subscriber::fmt::try_init(); // Try init, ignore if already initialized

    println!("⏱️  Testing 10-confirmation safety (COMIT standard)...");
    println!("   This will take ~20 minutes (10 blocks × 2 min)");

    let wallet = MoneroWallet::new(
        "http://localhost:38088/json_rpc".to_string(),
        "http://stagenet.xmr-tw.org:38081".to_string(),
        "atomic-swap-test".to_string(),
    ).await?;

    wallet.open_wallet("test123").await?;

    // Check balance first
    let (balance, unlocked_balance) = wallet.get_balance().await?;
    println!("💰 Wallet balance: {} XMR (unlocked: {} XMR)", 
             piconero_to_xmr(balance), piconero_to_xmr(unlocked_balance));
    
    if balance == 0 {
        println!("⚠️  Wallet has 0 balance. Skipping test.");
        println!("💡 Fund wallet via: https://stagenet-faucet.xmr-tw.org/");
        println!("   Address: {}", wallet.get_address().await?);
        return Ok(()); // Skip test if unfunded
    }

    // Create test transaction
    let destination = wallet.get_address().await?;
    let amount_piconero = xmr_to_piconero(0.01);
    
    // Ensure we have enough balance
    if balance < amount_piconero {
        println!("⚠️  Insufficient balance. Need {} XMR, have {} XMR", 
                 piconero_to_xmr(amount_piconero), piconero_to_xmr(balance));
        return Ok(()); // Skip test if insufficient balance
    }
    
    let current_height = wallet.get_height().await?;

    let result = wallet.transfer_locked(
        &destination,
        amount_piconero,
        current_height + 10,
    ).await?;

    println!("✅ Transaction created: {}", result.tx_hash);
    println!("⏳ Waiting for 10 confirmations (COMIT production standard)...");

    let start = std::time::Instant::now();
    wallet.wait_for_confirmations(&result.tx_hash, 10).await?;
    let duration = start.elapsed();

    println!("✅ 10 confirmations received!");
    println!("⏱️  Duration: {:.2} minutes", duration.as_secs_f64() / 60.0);
    println!("📊 Average block time: {:.2} minutes", 
             duration.as_secs_f64() / 60.0 / 10.0);

    // Should be ~20 minutes (2 min per block)
    assert!(duration.as_secs() > 600);  // At least 10 minutes
    assert!(duration.as_secs() < 1800); // Less than 30 minutes

    Ok(())
}

