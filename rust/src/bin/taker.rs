//! Taker (Bob) CLI for XMR↔Starknet atomic swap demo.
//!
//! This command:
//! 1. Watches for AtomicLock contracts on Starknet Sepolia
//! 2. When conditions are met, prepares the reveal_secret(secret) action
//! 3. Reveals the secret `t` via the SecretRevealed event
//! 4. Maker can then finalize Monero signature

use anyhow::{Context, Result};
use clap::Parser;
use xmr_secret_gen::starknet::{watch_unlocked_events, StarknetClient};

#[derive(Parser)]
#[command(name = "taker")]
#[command(about = "Taker (Bob) side of XMR↔Starknet atomic swap")]
struct Args {
    /// Starknet RPC URL (default: Sepolia testnet)
    #[arg(
        long,
        default_value = "https://api.zan.top/public/starknet-sepolia/rpc/v0_10"
    )]
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
        if let Some(contract_addr) = args.contract_address.as_deref() {
            let secret_hash = watch_unlocked_events(&starknet_client, contract_addr, 10).await?;
            println!("   Secret hash word observed: {}", secret_hash);
        } else {
            println!("   Provide --contract-address to watch a known AtomicLock instance");
            println!("   Discovery of new deployments should be done with indexed ContractDeployed events");
        }
    } else if let Some(contract_addr) = args.contract_address {
        println!("\n🔓 Unlocking contract: {}", contract_addr);

        if let Some(secret_hex) = args.secret {
            println!("   Secret provided: {}", secret_hex);

            // Convert secret to ByteArray format for Cairo
            let _secret_bytes = hex::decode(&secret_hex).context("Invalid secret hex")?;

            #[cfg(feature = "full-integration")]
            {
                if let Some(account_path) = args.starknet_account {
                    let _ = account_path;
                    anyhow::bail!(
                        "taker does not sign Starknet reveal transactions safely yet. Use the TypeScript/starknet.js path for reveal_secret/claim_tokens; refusing to return a placeholder transaction hash."
                    );
                } else {
                    println!("   Full contract interaction requires signed TypeScript/starknet.js tooling");
                    println!("\n   Manual unlock command:");
                    println!("   starknet invoke \\");
                    println!("     --address {} \\", contract_addr);
                    println!("     --function reveal_secret \\");
                    println!("     --inputs {}", secret_hex);
                }
            }

            #[cfg(not(feature = "full-integration"))]
            {
                println!("   Contract interaction requires signed TypeScript/starknet.js tooling");
                println!("\n   Manual unlock command:");
                println!("   starknet invoke \\");
                println!("     --address {} \\", contract_addr);
                println!("     --function reveal_secret \\");
                println!("     --inputs {}", secret_hex);
            }
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
    println!("   2. When ready, call reveal_secret(secret), then claim_tokens after grace");
    println!("   3. Secret `t` will be revealed via SecretRevealed event");
    println!("   4. Maker can finalize Monero signature");

    Ok(())
}
