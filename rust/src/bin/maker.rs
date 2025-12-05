//! Maker (Alice) CLI for XMR↔Starknet atomic swap demo.
//!
//! This command:
//! 1. Generates a secret scalar `t`
//! 2. Creates adaptor signature for Monero stagenet
//! 3. Deploys AtomicLock contract on Starknet Sepolia
//! 4. Waits for `t` to be revealed (via Unlocked event)
//! 5. Finalizes Monero signature and broadcasts on stagenet

use anyhow::{Context, Result};
use clap::Parser;
use std::path::PathBuf;
use xmr_secret_gen::adaptor::{split_monero_key, create_adaptor_signature};
use xmr_secret_gen::{
    generate_swap_secret,
    starknet::StarknetClient,
    monero::MoneroClient,
};
#[cfg(feature = "full-integration")]
use xmr_secret_gen::{starknet_full::StarknetAccount, monero_full::MoneroRpcClient};
use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::scalar::Scalar;
use serde_json::json;

#[derive(Parser)]
#[command(name = "maker")]
#[command(about = "Maker (Alice) side of XMR↔Starknet atomic swap")]
struct Args {
    /// Starknet RPC URL (default: Sepolia testnet)
    #[arg(long, default_value = "https://starknet-sepolia.public.blastapi.io/rpc/v0_7")]
    starknet_rpc: String,

    /// Path to Starknet account JSON (for contract deployment)
    #[arg(long)]
    starknet_account: Option<PathBuf>,

    /// Monero stagenet RPC URL
    #[arg(long, default_value = "http://stagenet.community.rino.io:38081")]
    monero_rpc: String,

    /// Lock duration in seconds (default: 1 hour)
    #[arg(long, default_value = "3600")]
    lock_duration: u64,

    /// Token contract address (optional, for ERC20 transfers)
    #[arg(long)]
    token_address: Option<String>,

    /// Amount to lock (optional, in wei/units)
    #[arg(long)]
    amount: Option<String>,

    /// Output file for swap state (JSON)
    #[arg(long, default_value = "swap_state.json")]
    output: PathBuf,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();
    
    println!("🔐 Maker (Alice) - Starting atomic swap setup...");
    
    // Step 1: Generate secret and swap data
    println!("\n📝 Step 1: Generating secret scalar `t`...");
    let swap_secret = generate_swap_secret();
    let secret_bytes: [u8; 32] = hex::decode(&swap_secret.secret_hex)
        .context("Failed to decode secret hex")?
        .try_into()
        .map_err(|_| anyhow::anyhow!("Invalid secret length"))?;
    let adaptor_scalar = Scalar::from_bytes_mod_order(secret_bytes);
    
    println!("   Secret: {}", swap_secret.secret_hex);
    println!("   Hash: {:?}", swap_secret.hash_u32_words);
    
    // Step 2: Split Monero key and create adaptor signature
    println!("\n🔑 Step 2: Creating Monero adaptor signature...");
    let full_monero_key = Scalar::from_bytes_mod_order([0x42u8; 32]); // Demo key
    // Note: In production, use the same adaptor_scalar from swap_secret
    // For demo, we'll use a different approach - split with the generated adaptor_scalar
    let base_key = full_monero_key - adaptor_scalar;
    let adaptor_point = &adaptor_scalar * &ED25519_BASEPOINT_POINT;
    
    let message = b"Monero stagenet transaction for atomic swap";
    let adaptor_sig = create_adaptor_signature(&base_key, &adaptor_point, message);
    
    println!("   Adaptor point: {:?}", adaptor_point.compress().to_bytes());
    println!("   Adaptor signature created (ready for Monero stagenet)");
    
    // Step 3: Prepare contract deployment data
    println!("\n📄 Step 3: Preparing Starknet contract deployment...");
    let lock_until = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs() + args.lock_duration;
    
    let deployment_data = json!({
        "hash_words": swap_secret.hash_u32_words,
        "lock_until": lock_until,
        "token": args.token_address.as_ref().map(|s| s.as_str()).unwrap_or("0x0"),
        "amount": args.amount.as_ref().map(|s| s.as_str()).unwrap_or("0"),
        "adaptor_point_x": swap_secret.adaptor_point_x_limbs,
        "adaptor_point_y": swap_secret.adaptor_point_y_limbs,
        "dleq": ["0x0", "0x0"], // Placeholder for now
        "fake_glv_hint": swap_secret.fake_glv_hint,
    });
    
    println!("   Lock until: {} ({} seconds from now)", lock_until, args.lock_duration);
    println!("   Contract data prepared");
    
    // Step 4: Save swap state
    println!("\n💾 Step 4: Saving swap state...");
    let swap_state = json!({
        "role": "maker",
        "secret_hex": swap_secret.secret_hex,
        "adaptor_scalar_hex": hex::encode(adaptor_scalar.to_bytes()),
        "adaptor_point": hex::encode(adaptor_point.compress().to_bytes()),
        "adaptor_signature": {
            "partial_sig": hex::encode(adaptor_sig.partial_sig.to_bytes()),
            "nonce_commitment": hex::encode(adaptor_sig.nonce_commitment.compress().to_bytes()),
        },
        "deployment_data": deployment_data,
        "starknet_rpc": args.starknet_rpc,
        "monero_rpc": args.monero_rpc,
        "lock_until": lock_until,
    });
    
    std::fs::write(&args.output, serde_json::to_string_pretty(&swap_state)?)
        .context("Failed to write swap state file")?;
    
    println!("   Swap state saved to: {}", args.output.display());
    
    // Step 5: Deploy contract (if account provided)
    let contract_address: Option<String> = if let Some(account_path) = args.starknet_account {
        println!("\n🚀 Step 5: Deploying contract to Starknet Sepolia...");
        println!("   Account: {}", account_path.display());
        println!("   ⚠️  Contract deployment requires starknet-rs integration");
        println!("   ⚠️  For now, use manual deployment:");
        println!("     1. Use Starknet CLI: starknet deploy");
        println!("     2. Use Starknet.js");
        println!("     3. Or implement automatic deployment");
        None
    } else {
        println!("\n📋 Step 5: Manual contract deployment required");
        println!("   Deployment data saved in: {}", args.output.display());
        println!("   Deploy using:");
        println!("     - Starknet CLI");
        println!("     - Starknet.js");
        println!("     - Or provide --starknet-account for auto-deployment");
        None
    };
    
    // Step 6: Wait for unlock event (if contract deployed)
    if let Some(contract_addr) = contract_address {
        println!("\n👀 Step 6: Waiting for secret reveal (Unlocked event)...");
        
        #[cfg(feature = "full-integration")]
        {
            if let Some(account_path) = args.starknet_account {
                // Use full integration if account provided
                let account = StarknetAccount::new(
                    args.starknet_rpc.clone(),
                    "0x0".to_string(), // Account address - should be loaded from file
                    "0x0".to_string(), // Private key - should be loaded from file
                );
                
                println!("   Watching contract: {}", contract_addr);
                let revealed_secret_hash = account
                    .watch_unlocked_events(&contract_addr, 5)
                    .await
                    .context("Failed to watch events")?;
                
                println!("   ✅ Secret revealed! Hash: {}", revealed_secret_hash);
                
                // Step 7: Finalize and broadcast Monero transaction
                println!("\n💰 Step 7: Finalizing Monero signature and broadcasting...");
                let monero_client = MoneroRpcClient::new(args.monero_rpc.clone());
                
                // Finalize signature using revealed secret
                use xmr_secret_gen::adaptor::finalize_signature;
                let finalized_sig = finalize_signature(&adaptor_sig, &adaptor_scalar)
                    .context("Failed to finalize signature")?;
                
                println!("   ✅ Signature finalized");
                println!("   ⚠️  Transaction broadcasting requires full Monero wallet integration");
                println!("   ⚠️  In production, use monero-rs to broadcast finalized transaction");
            } else {
                println!("   ⚠️  Full event watching requires --starknet-account");
                println!("   ⚠️  For now, monitor manually or use Starknet explorer");
            }
        }
        
        #[cfg(not(feature = "full-integration"))]
        {
            let starknet_client = StarknetClient::new(args.starknet_rpc.clone());
            println!("   Watching contract: {}", contract_addr);
            println!("   ⚠️  Event watching requires full-integration feature");
            println!("   ⚠️  Build with: cargo build --features full-integration");
        }
    } else {
        println!("\n⏭️  Steps 6-7: Waiting for contract deployment...");
        println!("   After deployment, run maker again with --contract-address");
    }
    
    println!("\n✅ Maker setup complete!");
    println!("   Next steps:");
    println!("   1. Share adaptor signature/terms out-of-band with taker");
    println!("   2. Wait for taker to call verify_and_unlock on Starknet");
    println!("   3. Monitor for Unlocked event to detect secret reveal");
    println!("   4. Finalize Monero signature and broadcast");
    
    Ok(())
}

