//! Maker (Alice) CLI for XMR↔Starknet atomic swap artifact generation.
//!
//! This command:
//! 1. Generates a secret scalar `t`
//! 2. Creates adaptor signature for Monero stagenet
//! 3. Writes local JSON artifacts for the audited deployment tooling.
//!
//! This binary does not deploy contracts, sign Starknet transactions, or
//! broadcast Monero transactions. Use scripts/deploy.ts and wallet-rpc tooling
//! for those production steps.

use anyhow::{Context, Result};
use clap::Parser;
use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::scalar::Scalar;
use serde_json::json;
use std::path::PathBuf;
use xmr_secret_gen::adaptor::create_adaptor_signature;
use xmr_secret_gen::generate_swap_secret;

#[derive(Parser)]
#[command(name = "maker")]
#[command(about = "Maker (Alice) side of XMR↔Starknet atomic swap")]
struct Args {
    /// Starknet RPC URL (default: Sepolia testnet)
    #[arg(
        long,
        default_value = "https://api.zan.top/public/starknet-sepolia/rpc/v0_10"
    )]
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

    println!("Maker (Alice) - generating atomic swap artifacts...");

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

    println!(
        "   Adaptor point: {:?}",
        adaptor_point.compress().to_bytes()
    );
    println!("   Adaptor signature created (ready for Monero stagenet)");

    // Step 3: Prepare contract artifact data. This is not complete deployment calldata:
    // DLEQ MSM hints must come from tools/regenerate_dleq_hints.py.
    println!("\nStep 3: Preparing Starknet contract artifacts...");
    let lock_until = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
        + args.lock_duration;

    let deployment_data = json!({
        "status": "artifact-only; use tools/generate_deploy_calldata.py or scripts/deploy.ts for signed constructor calldata",
        "hash_words": swap_secret.hash_u32_words,
        "lock_until": lock_until,
        "token": args.token_address.as_ref().map(|s| s.as_str()).unwrap_or("0x0"),
        "amount": args.amount.as_ref().map(|s| s.as_str()).unwrap_or("0"),
        "adaptor_point_x": &swap_secret.adaptor_point_x_limbs,
        "adaptor_point_y": &swap_secret.adaptor_point_y_limbs,
        "adaptor_point_compressed": &swap_secret.adaptor_point_compressed,
        "adaptor_point_sqrt_hint": &swap_secret.adaptor_point_sqrt_hint,
        "dleq_second_point_compressed": &swap_secret.dleq_second_point_compressed,
        "dleq_second_point_sqrt_hint": &swap_secret.dleq_second_point_sqrt_hint,
        "dleq": {
            "challenge": &swap_secret.dleq_challenge,
            "response": &swap_secret.dleq_response,
        },
        "dleq_r1_compressed": &swap_secret.dleq_r1_compressed,
        "dleq_r1_sqrt_hint": &swap_secret.dleq_r1_sqrt_hint,
        "dleq_r2_compressed": &swap_secret.dleq_r2_compressed,
        "dleq_r2_sqrt_hint": &swap_secret.dleq_r2_sqrt_hint,
        "fake_glv_hint": &swap_secret.fake_glv_hint,
        "dleq_msm_hints": "not generated by maker; run uv run --project tools python tools/regenerate_dleq_hints.py",
    });

    println!(
        "   Lock until: {} ({} seconds from now)",
        lock_until, args.lock_duration
    );
    println!("   Contract artifact data prepared");

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

    // Step 5: Deployment is intentionally outside this artifact generator.
    if let Some(account_path) = args.starknet_account.as_ref() {
        println!("\nStep 5: Starknet deployment requested...");
        println!("   Account: {}", account_path.display());
        anyhow::bail!(
            "maker does not sign or deploy Starknet transactions. Use scripts/deploy.ts after generating canonical calldata; refusing to continue with placeholder deployment."
        );
    } else {
        println!("\nStep 5: Signed deployment required outside maker");
        println!("   Deployment data saved in: {}", args.output.display());
        println!("   Use: uv run --project tools python tools/regenerate_dleq_hints.py");
        println!("   Then: tools/generate_deploy_calldata.py or scripts/deploy.ts");
    }
    println!("\nSteps 6-7: Not started by maker");
    println!("   After reveal, finalize Monero through the VM wallet-rpc flow.");

    println!("\nMaker artifact generation complete.");
    println!("   Next steps:");
    println!("   1. Share adaptor signature/terms out-of-band with taker");
    println!("   2. Deploy with the TypeScript/starknet.js path, not this binary");
    println!("   3. Monitor SecretRevealed/TokensClaimed events with ABI-aware tooling");
    println!("   4. Finalize/broadcast Monero only through the VM wallet-rpc setup");

    Ok(())
}
