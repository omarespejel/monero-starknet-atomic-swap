//! Taker (Bob) CLI for XMR↔Starknet atomic swap demo.
//!
//! This command:
//! 1. Watches for AtomicLock contracts on Starknet Sepolia
//! 2. When conditions are met, calls verify_and_unlock(secret)
//! 3. Reveals the secret `t` via the Unlocked event
//! 4. Maker can then finalize Monero signature

use anyhow::{Context, Result};
use clap::Parser;
use xmr_secret_gen::starknet::StarknetClient;
use serde_json::json;

#[derive(Parser)]
#[command(name = "taker")]
#[command(about = "Taker (Bob) side of XMR↔Starknet atomic swap")]
struct Args {
    /// Starknet RPC URL (default: Sepolia testnet)
    #[arg(long, default_value = "https://starknet-sepolia.public.blastapi.io/rpc/v0_7")]
    starknet_rpc: String,

    /// Path to Starknet account JSON (for contract interaction)
    #[arg(long)]
    starknet_account: Option<String>,

    /// Contract address to watch/unlock
    #[arg(long)]
    contract_address: Option<String>,

    /// Secret to use for unlock (if known)
    #[arg(long)]
    secret: Option<String>,

    /// Watch mode: continuously monitor for new contracts
    #[arg(long)]
    watch: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();
    
    println!("🔓 Taker (Bob) - Starting atomic swap participation...");
    
    let starknet_client = StarknetClient::new(args.starknet_rpc.clone());
    
    if args.watch {
        println!("\n👀 Watch mode: Monitoring for AtomicLock contracts...");
        println!("   ⚠️  Contract watching requires event filtering");
        println!("   ⚠️  Implement: Filter for AtomicLock contract deployments");
        println!("   ⚠️  When found, extract contract address and terms");
    } else if let Some(contract_addr) = args.contract_address {
        println!("\n🔓 Unlocking contract: {}", contract_addr);
        
        if let Some(secret_hex) = args.secret {
            println!("   Secret provided: {}", secret_hex);
            
            // Convert secret to ByteArray format for Cairo
            let _secret_bytes = hex::decode(&secret_hex)
                .context("Invalid secret hex")?;
            
            println!("   ⚠️  Contract interaction requires account signing");
            println!("   ⚠️  In production, use starknet-rs to:");
            println!("      1. Create account client");
            println!("      2. Call verify_and_unlock(secret_bytes)");
            println!("      3. Wait for transaction confirmation");
            
            // In production, uncomment:
            // let account = load_account(&args.starknet_account)?;
            // let result = account.call_contract(
            //     &contract_addr,
            //     "verify_and_unlock",
            //     vec![secret_bytes],
            // ).await?;
            // println!("   ✅ Unlock successful! TX: {}", result.transaction_hash);
            
            println!("\n   Manual unlock command:");
            println!("   starknet invoke \\");
            println!("     --address {} \\", contract_addr);
            println!("     --function verify_and_unlock \\");
            println!("     --inputs {}", secret_hex);
        } else {
            println!("   ⚠️  Secret required for unlock");
            println!("   ⚠️  Provide --secret <hex>");
            println!("   ⚠️  Secret should be 32 bytes (64 hex chars)");
        }
    } else {
        println!("\n❌ Error: Either --watch or --contract-address required");
        println!("   Use --watch to monitor for contracts");
        println!("   Use --contract-address <addr> --secret <hex> to unlock");
    }
    
    println!("\n✅ Taker ready!");
    println!("   Next steps:");
    println!("   1. Watch for AtomicLock contracts or use known address");
    println!("   2. When ready, call verify_and_unlock(secret)");
    println!("   3. Secret `t` will be revealed via Unlocked event");
    println!("   4. Maker can finalize Monero signature");
    
    Ok(())
}

