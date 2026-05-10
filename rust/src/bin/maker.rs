//! Maker (Alice) CLI for XMR↔Starknet atomic swap artifact generation.
//!
//! This command:
//! 1. Generates two-party Monero key shares
//! 2. Derives the Starknet hashlock/DLEQ package from Bob's raw reveal bytes
//! 3. Writes local JSON artifacts for the audited deployment tooling.
//!
//! This binary does not deploy contracts, sign Starknet transactions, or
//! broadcast Monero transactions. Use scripts/deploy.ts and wallet-rpc tooling
//! for those production steps.

use anyhow::{Context, Result};
use clap::Parser;
use serde_json::json;
use std::io::Write;
use std::path::{Path, PathBuf};
use xmr_secret_gen::monero::{AliceKeys, BobKeys, SharedOutput};
use xmr_secret_gen::swap::{
    MoneroNetwork, StarknetPrivacySettlement, StarknetReceiveMode, SwapDirection, SwapTerms,
    MIN_LOCK_DURATION_SECS, TERMS_DEFAULT_MONERO_CONFIRMATIONS,
};
use xmr_secret_gen::try_generate_swap_secret_from_bytes;

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

    /// Swap direction: xmr_to_starknet or starknet_to_xmr
    #[arg(long, default_value = "xmr_to_starknet")]
    direction: String,

    /// Monero network: mainnet, stagenet, or testnet
    #[arg(long, default_value = "stagenet")]
    monero_network: String,

    /// Starknet receive mode: public_address or privacy_open_note
    #[arg(long, default_value = "public_address")]
    starknet_receive_mode: String,

    /// Lock duration in seconds (default: 3 hours, matching the contract minimum)
    #[arg(long, default_value_t = MIN_LOCK_DURATION_SECS)]
    lock_duration: u64,

    /// Token contract address. Required to emit validated swap_terms.
    #[arg(long)]
    token_address: Option<String>,

    /// Starknet token amount to lock, in token base units. Required to emit validated swap_terms.
    #[arg(long)]
    amount: Option<String>,

    /// Expected Monero amount, in piconero. Required to emit validated swap_terms.
    #[arg(long)]
    expected_monero_amount_piconero: Option<u64>,

    /// Privacy pool contract for xmr_to_starknet + privacy_open_note terms.
    #[arg(long)]
    privacy_pool_address: Option<String>,

    /// AtomicSwapPrivacyHelper contract for xmr_to_starknet + privacy_open_note terms.
    #[arg(long)]
    privacy_helper_address: Option<String>,

    /// SDK-generated privacy-pool open note id for private STRK receive.
    #[arg(long)]
    privacy_open_note_id: Option<String>,

    /// Output file for swap state (JSON)
    #[arg(long, default_value = "swap_state.json")]
    output: PathBuf,

    /// Print the local reveal secret to stdout. Off by default to avoid terminal/history leakage.
    #[arg(long)]
    print_secret: bool,
}

#[tokio::main]
async fn main() -> Result<()> {
    let args = Args::parse();

    println!("Maker (Alice) - generating atomic swap artifacts...");

    let direction = args
        .direction
        .parse::<SwapDirection>()
        .context("Invalid --direction")?;
    let monero_network = args
        .monero_network
        .parse::<MoneroNetwork>()
        .context("Invalid --monero-network")?;
    let starknet_receive_mode = args
        .starknet_receive_mode
        .parse::<StarknetReceiveMode>()
        .context("Invalid --starknet-receive-mode")?;

    // Step 1: Generate two-party Monero key shares and derive swap data.
    println!("\n📝 Step 1: Generating two-party Monero key shares...");
    let alice_keys = AliceKeys::generate();
    let bob_keys = BobKeys::generate();
    let shared_output = SharedOutput::new(&alice_keys, &bob_keys);
    let alice_public = alice_keys.public_data();
    let bob_public = bob_keys.public_data();

    let swap_secret = try_generate_swap_secret_from_bytes(bob_keys.secret_bytes())
        .context("Failed to generate Starknet DLEQ package from Bob reveal bytes")?;
    let expected_hash_words: [u32; 8] = core::array::from_fn(|i| {
        let start = i * 4;
        u32::from_be_bytes(bob_keys.hashlock()[start..start + 4].try_into().unwrap())
    });
    anyhow::ensure!(
        swap_secret.hash_u32_words == expected_hash_words,
        "two-party Bob hashlock does not match Starknet deployment hash words"
    );

    if args.print_secret {
        println!("   Secret: {}", swap_secret.secret_hex);
    } else {
        println!("   Secret: <written only to local artifact; pass --print-secret to display>");
    }
    println!("   Hash: {:?}", swap_secret.hash_u32_words);

    // Step 2: Verify the key-share package that wallet-rpc recovery will use.
    println!("\n🔑 Step 2: Preparing two-party Monero key exchange artifact...");
    println!(
        "   Alice spend share public: {}",
        hex::encode(alice_public.S_a)
    );
    println!("   Bob adaptor point: {}", hex::encode(bob_public.S_b));
    println!(
        "   Shared spend public key: {}",
        hex::encode(shared_output.S.compress().to_bytes())
    );

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

    let swap_terms = match (
        args.token_address.as_ref(),
        args.amount.as_ref(),
        args.expected_monero_amount_piconero,
    ) {
        (Some(token), Some(amount), Some(monero_amount_piconero)) => {
            let starknet_amount = amount
                .parse::<u128>()
                .context("--amount must be an integer token base-unit amount")?;
            let starknet_privacy_settlement = match (
                args.privacy_pool_address.as_ref(),
                args.privacy_helper_address.as_ref(),
                args.privacy_open_note_id.as_ref(),
            ) {
                (None, None, None) => None,
                (Some(pool), Some(helper), Some(note_id)) => Some(StarknetPrivacySettlement {
                    privacy_pool_address: pool.clone(),
                    privacy_helper_address: helper.clone(),
                    open_note_id: note_id.clone(),
                    open_note_token: token.clone(),
                    open_note_amount: starknet_amount,
                }),
                _ => anyhow::bail!(
                    "--privacy-pool-address, --privacy-helper-address, and --privacy-open-note-id must be provided together"
                ),
            };
            let terms = SwapTerms {
                swap_id: uuid::Uuid::new_v4().to_string(),
                direction,
                monero_network,
                monero_amount_piconero,
                starknet_amount,
                starknet_token: token.clone(),
                lock_duration_secs: args.lock_duration,
                monero_confirmations: TERMS_DEFAULT_MONERO_CONFIRMATIONS,
                starknet_receive_mode,
                starknet_privacy_settlement,
            };
            terms.validate().context("Invalid swap terms")?;
            Some(terms)
        }
        _ => None,
    };

    println!(
        "   Lock until: {} ({} seconds from now)",
        lock_until, args.lock_duration
    );
    println!("   Contract artifact data prepared");
    if swap_terms.is_some() {
        println!("   Validated swap terms included");
    } else {
        println!("   Swap terms not emitted: provide --token-address, --amount, and --expected-monero-amount-piconero");
    }

    // Step 4: Save swap state
    println!("\n💾 Step 4: Saving swap state...");
    let swap_state = json!({
        "role": "maker",
        "artifact_version": 3,
        "protocol": "two_party_key_generation_v1",
        "secret_warning": "local-only reveal preimage; do not share before Starknet claim",
        "privacy_warning": "view-share scalars and shared view scalar are local wallet-scanning material; do not share them as public quote data",
        "secret_hex": swap_secret.secret_hex,
        "monero_key_exchange": {
            "alice_public": {
                "spend_share_point": hex::encode(alice_public.S_a),
                "view_share_point": hex::encode(alice_public.V_a),
            },
            "alice_private_local": {
                "spend_share_scalar": hex::encode(alice_keys.spend_share().to_bytes()),
                "view_share_scalar": hex::encode(alice_keys.view_share().to_bytes()),
            },
            "bob_public": {
                "spend_share_point": hex::encode(bob_public.S_b),
                "view_share_point": hex::encode(bob_public.V_b),
                "hashlock": hex::encode(bob_public.hashlock),
            },
            "bob_private_local": {
                "view_share_scalar": hex::encode(bob_keys.view_share().to_bytes()),
            },
            "shared_output": {
                "spend_public_key": hex::encode(shared_output.S.compress().to_bytes()),
                "view_public_key": hex::encode(shared_output.V.compress().to_bytes()),
            },
            "shared_view_material_local": {
                "view_scalar": hex::encode(shared_output.v.to_bytes()),
            },
        },
        "deployment_data": deployment_data,
        "swap_terms": swap_terms,
        "starknet_rpc": args.starknet_rpc,
        "monero_rpc": args.monero_rpc,
        "lock_until": lock_until,
    });

    write_secret_artifact(&args.output, &serde_json::to_string_pretty(&swap_state)?)
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
    println!("   1. Share public key-exchange data and terms out-of-band with taker");
    println!("   2. Deploy with the TypeScript/starknet.js path, not this binary");
    println!("   3. Monitor SecretRevealed/TokensClaimed events with ABI-aware tooling");
    println!("   4. Finalize/broadcast Monero only through the VM wallet-rpc setup");

    Ok(())
}

fn write_secret_artifact(path: &Path, contents: &str) -> Result<()> {
    #[cfg(unix)]
    {
        use std::fs::{self, OpenOptions};
        use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

        let mut file = OpenOptions::new()
            .write(true)
            .create(true)
            .truncate(true)
            .mode(0o600)
            .open(path)?;
        file.write_all(contents.as_bytes())?;
        file.sync_all()?;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
        Ok(())
    }

    #[cfg(not(unix))]
    {
        std::fs::write(path, contents)?;
        Ok(())
    }
}
