//! Taker (Bob) CLI for XMR↔Starknet atomic swap demo.
//!
//! This command:
//! 1. Watches for AtomicLock contracts on Starknet Sepolia
//! 2. When conditions are met, prepares the reveal_secret(secret) action
//! 3. Reveals the secret `t` via the SecretRevealed event
//! 4. Maker can then recover and sweep Monero through wallet-rpc

use anyhow::{anyhow, Context, Result};
use clap::Parser;
use xmr_secret_gen::starknet::{watch_unlocked_events, StarknetClient};
use zeroize::Zeroize;

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

        if let Some(mut secret_hex) = args.secret {
            validate_secret(&secret_hex).context("Invalid --secret")?;
            secret_hex.zeroize();
            println!("   Secret provided: <validated, not printed>");

            #[cfg(feature = "full-integration")]
            {
                if let Some(account_path) = args.starknet_account {
                    let _ = account_path;
                    anyhow::bail!(
                        "taker does not sign Starknet reveal transactions safely yet. Use the TypeScript/starknet.js path for reveal_secret/claim_tokens; refusing to return a placeholder transaction hash."
                    );
                } else {
                    print_reveal_instructions(&contract_addr);
                }
            }

            #[cfg(not(feature = "full-integration"))]
            {
                print_reveal_instructions(&contract_addr);
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
    println!("   4. Maker can recover and sweep Monero through the VM wallet-rpc flow");

    Ok(())
}

fn validate_secret(secret_hex: &str) -> Result<()> {
    let hex_str = secret_hex.strip_prefix("0x").unwrap_or(secret_hex);
    let mut bytes = hex::decode(hex_str).context("secret must be hex")?;
    let byte_len = bytes.len();
    bytes.zeroize();
    if byte_len != 32 {
        return Err(anyhow!("secret must be 32 bytes, got {}", byte_len));
    }
    Ok(())
}

fn print_reveal_instructions(contract_addr: &str) {
    println!("   Signed reveal should use the maintained sncast helper.");
    println!("   Put the secret in ATOMIC_SWAP_SECRET_HEX outside shell history, then run:");
    println!(
        "     scripts/atomic_lock_sncast_ops.sh reveal {}",
        contract_addr
    );
}
