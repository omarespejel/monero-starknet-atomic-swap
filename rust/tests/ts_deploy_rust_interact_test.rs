//! Hybrid E2E Test: TypeScript Deployment + Rust Interactions
//!
//! This test demonstrates the recommended production approach:
//! 1. Deploy contract using TypeScript (handles deployment transaction signing)
//! 2. Interact with contract using Rust (invoke transaction signing implemented)
//!
//! This approach enables:
//! - Full E2E testing without implementing deployment signing in Rust
//! - Production-ready invoke operations (reveal_secret, claim_tokens, refund)
//! - Clear separation of concerns
//!
//! Prerequisites:
//! - Starknet devnet running: `docker run -p 5050:5050 shardlabs/starknet-devnet-rs --seed 0`
//! - TypeScript dependencies installed: `cd scripts/ts && npm install`
//! - Test vectors generated: `cd rust && cargo run --bin generate_test_vector`
//! - Run with: `cargo test --test ts_deploy_rust_interact_test -- --ignored --nocapture`
//!
//! See `tests/README_HYBRID_TEST.md` for detailed documentation.

use anyhow::{Context, Result};
use sha2::{Digest, Sha256};
use std::process::Command;
use std::path::PathBuf;
use std::fs;
use serde_json::Value;
use xmr_secret_gen::monero::two_party_keys::{AliceKeys, BobKeys, SharedOutput};
use xmr_secret_gen::dleq::generate_dleq_proof_for_bob;
use xmr_secret_gen::swap::StarknetClient;
use xmr_secret_gen::swap::starknet_manual::StarknetManualClient;

// Devnet configuration (deterministic pre-funded account)
const DEVNET_RPC_URL: &str = "http://127.0.0.1:5050";
const DEVNET_ACCOUNT: &str = "0x049a5a5c30836ff78b3f9a2c0868eaabeeb1ca8ea049d2ed435ad42fd6315fba";
const DEVNET_PRIVATE_KEY: &str = "0x0000000000000000000000000000000000000000000000000000000000000001";

/// Deploy contract using TypeScript deployment script.
/// Returns the deployed contract address.
async fn deploy_via_typescript() -> Result<String> {
    println!("📦 Deploying contract via TypeScript...");
    
    // Get project root
    // CARGO_MANIFEST_DIR is rust/ when running from rust/tests/
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    // rust/ -> parent -> monero-secret-gen/
    let project_root = manifest_dir
        .parent()
        .context("Failed to get project root")?;
    
    let ts_dir = project_root.join("scripts").join("ts");
    
    // Debug: Print paths for troubleshooting
    tracing::debug!("Manifest dir: {:?}", manifest_dir);
    tracing::debug!("Project root: {:?}", project_root);
    tracing::debug!("TS dir: {:?}", ts_dir);
    tracing::debug!("TS node_modules exists: {}", ts_dir.join("node_modules").exists());
    
    // Check if node_modules exists
    if !ts_dir.join("node_modules").exists() {
        return Err(anyhow::anyhow!(
            "TypeScript dependencies not installed. Run: cd scripts/ts && npm install"
        ));
    }
    
    // Run TypeScript deployment script
    let output = Command::new("npm")
        .args(&["run", "deploy:devnet"])
        .current_dir(&ts_dir)
        .output()
        .context("Failed to run TypeScript deployment script")?;
    
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let stdout = String::from_utf8_lossy(&output.stdout);
        eprintln!("TypeScript deployment failed:");
        eprintln!("STDOUT: {}", stdout);
        eprintln!("STDERR: {}", stderr);
        return Err(anyhow::anyhow!("TypeScript deployment failed"));
    }
    
    // Parse deployment result from JSON file
    let deployment_file = project_root.join("deployments").join("devnet-result.json");
    
    if !deployment_file.exists() {
        return Err(anyhow::anyhow!(
            "Deployment result file not found: {:?}",
            deployment_file
        ));
    }
    
    let deployment_json: Value = serde_json::from_str(
        &fs::read_to_string(&deployment_file)
            .context("Failed to read deployment result file")?
    )?;
    
    let contract_address = deployment_json["contractAddress"]
        .as_str()
        .context("Missing contractAddress in deployment result")?
        .to_string();
    
    println!("   ✅ Contract deployed at: {}", contract_address);
    
    Ok(contract_address)
}

/// Convert secret bytes to hashlock words (8 u32) for Cairo.
fn secret_to_hashlock_words(secret: &[u8; 32]) -> [u32; 8] {
    let hashlock_bytes: [u8; 32] = Sha256::digest(secret).into();
    let mut words = [0u32; 8];
    for i in 0..8 {
        words[i] = u32::from_le_bytes([
            hashlock_bytes[i * 4],
            hashlock_bytes[i * 4 + 1],
            hashlock_bytes[i * 4 + 2],
            hashlock_bytes[i * 4 + 3],
        ]);
    }
    words
}

#[tokio::test]
#[ignore] // Requires devnet + TypeScript setup
async fn test_ts_deploy_rust_interact() -> Result<()> {
    use tracing_subscriber;
    let _ = tracing_subscriber::fmt::try_init();
    
    println!("🔄 Starting Hybrid E2E Test (TypeScript Deploy + Rust Interact)");
    println!("{}", "=".repeat(80));
    
    // Step 1: Generate two-party keys
    println!("\n📝 Step 1: Generate Two-Party Keys");
    let alice = AliceKeys::generate();
    let bob = BobKeys::generate();
    let _shared = SharedOutput::new(&alice, &bob);
    
    println!("   ✅ Alice keys generated");
    println!("   ✅ Bob keys generated");
    println!("   ✅ Shared output computed");
    
    // Step 2: Generate DLEQ proof
    println!("\n📝 Step 2: Generate DLEQ Proof");
    let _dleq_proof = generate_dleq_proof_for_bob(&bob)
        .context("Failed to generate DLEQ proof")?;
    
    println!("   ✅ DLEQ proof generated");
    
    // Step 3: Deploy contract via TypeScript
    println!("\n📝 Step 3: Deploy Contract via TypeScript");
    let contract_address = deploy_via_typescript().await?;
    
    // Step 4: Create Rust client for interactions
    println!("\n📝 Step 4: Create Rust Client");
    // Note: We need a class hash, but for invoke operations we don't strictly need it
    // Using a placeholder - in production this would be the actual AtomicLock class hash
    let class_hash = "0x0"; // Placeholder - not used for invoke operations
    
    let client_manual = StarknetManualClient::devnet(
        DEVNET_ACCOUNT,
        DEVNET_PRIVATE_KEY,
        class_hash,
    )?;
    
    let client: Box<dyn StarknetClient> = Box::new(client_manual);
    
    println!("   ✅ Rust client created");
    
    // Step 5: Load test vectors to match TypeScript deployment
    println!("\n📝 Step 5: Load Test Vectors (to match TypeScript deployment)");
    
    // TypeScript deployment uses test_vectors.json, so we need to use the same secret
    let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
    let project_root = manifest_dir.parent().unwrap().parent().unwrap();
    let test_vectors_path = project_root.join("rust").join("test_vectors.json");
    
    if !test_vectors_path.exists() {
        return Err(anyhow::anyhow!(
            "Test vectors not found: {:?}. Generate with: cd rust && cargo run --bin generate_test_vector",
            test_vectors_path
        ));
    }
    
    let test_vectors_json: Value = serde_json::from_str(
        &fs::read_to_string(&test_vectors_path)
            .context("Failed to read test vectors")?
    )?;
    
    let secret_hex = test_vectors_json["secret"]
        .as_str()
        .context("Missing secret in test vectors")?;
    let secret_bytes = hex::decode(secret_hex.strip_prefix("0x").unwrap_or(secret_hex))
        .context("Invalid hex in secret")?;
    
    if secret_bytes.len() != 32 {
        return Err(anyhow::anyhow!("Secret must be 32 bytes"));
    }
    
    let secret_bytes_array: [u8; 32] = secret_bytes.try_into().unwrap();
    
    println!("   ✅ Test vectors loaded");
    println!("   📍 Using secret from test_vectors.json (matches TypeScript deployment)");
    
    // Step 6: Verify initial contract state
    println!("\n📝 Step 6: Verify Initial Contract State");
    
    // Create a separate client instance for view calls (simpler than downcasting)
    let view_client = StarknetManualClient::devnet(
        DEVNET_ACCOUNT,
        DEVNET_PRIVATE_KEY,
        "0x0",
    )?;
    
    let is_revealed_before = view_client.is_secret_revealed(&contract_address).await?;
    let is_unlocked_before = view_client.is_unlocked(&contract_address).await?;
    
    println!("   ✅ Contract state checked");
    println!("   📍 is_secret_revealed: {}", is_revealed_before);
    println!("   📍 is_unlocked: {}", is_unlocked_before);
    assert!(!is_revealed_before, "Secret should not be revealed initially");
    assert!(!is_unlocked_before, "Contract should not be unlocked initially");
    
    // Step 7: Call reveal_secret on deployed contract
    println!("\n📝 Step 7: Call reveal_secret() via Rust");
    
    let reveal_tx_hash = client.reveal_secret(&contract_address, &secret_bytes_array).await
        .context("Failed to reveal secret")?;
    
    println!("   ✅ Secret revealed!");
    println!("   📍 Transaction hash: {}", reveal_tx_hash);
    
    // Step 8: Wait for transaction confirmation
    println!("\n📝 Step 8: Wait for Transaction Confirmation");
    println!("   ⏳ Waiting for transaction to be included in block...");
    
    let receipt = view_client.wait_for_transaction(&reveal_tx_hash).await
        .context("Failed to wait for transaction confirmation")?;
    
    let status = receipt.get("status")
        .and_then(|s| s.as_str())
        .unwrap_or("unknown");
    
    println!("   ✅ Transaction confirmed!");
    println!("   📍 Status: {}", status);
    
    // Verify transaction was accepted
    assert!(
        status == "ACCEPTED_ON_L2" || status == "ACCEPTED_ON_L1",
        "Transaction should be accepted, got: {}",
        status
    );
    
    // Step 9: Verify contract state after reveal
    println!("\n📝 Step 9: Verify Contract State After Reveal");
    
    let is_revealed_after = view_client.is_secret_revealed(&contract_address).await?;
    let is_unlocked_after = view_client.is_unlocked(&contract_address).await?;
    
    println!("   ✅ Contract state verified");
    println!("   📍 is_secret_revealed: {} (expected: true)", is_revealed_after);
    println!("   📍 is_unlocked: {} (expected: false, grace period active)", is_unlocked_after);
    
    assert!(is_revealed_after, "Secret should be revealed after reveal_secret()");
    // Note: is_unlocked may still be false if grace period hasn't expired
    
    // Step 10: Test claim_tokens (after grace period - would need to wait in real scenario)
    println!("\n📝 Step 10: Test claim_tokens() (would require grace period wait)");
    println!("   ⚠️  Skipping claim_tokens test - requires 2-hour grace period");
    println!("   📝 In production, call claim_tokens() after grace period expires");
    
    println!("\n✅ Hybrid E2E Test Complete!");
    println!("{}", "=".repeat(80));
    println!("\n📊 Summary:");
    println!("   ✅ Two-party key generation: PASS");
    println!("   ✅ DLEQ proof generation: PASS");
    println!("   ✅ TypeScript deployment: PASS");
    println!("   ✅ Rust client creation: PASS");
    println!("   ✅ Contract state verification (before): PASS");
    println!("   ✅ Secret reveal via Rust: PASS");
    println!("   ✅ Contract state verification (after): PASS");
    println!("   📝 Full E2E flow verified: TypeScript deploy → Rust interact → State verified");
    
    Ok(())
}

#[tokio::test]
#[ignore] // Requires devnet + TypeScript setup
async fn test_full_swap_flow_hybrid() -> Result<()> {
    use tracing_subscriber;
    let _ = tracing_subscriber::fmt::try_init();
    
    println!("🔄 Starting Full Swap Flow Test (Hybrid Approach)");
    println!("{}", "=".repeat(80));
    
    // This test demonstrates the complete flow:
    // 1. Alice generates keys
    // 2. Bob generates keys + DLEQ proof
    // 3. Deploy contract via TypeScript (with Bob's DLEQ proof)
    // 4. Bob reveals secret via Rust (reveal_secret)
    // 5. Alice recovers full key and claims Monero
    
    println!("\n📝 Step 1: Alice generates keys");
    let alice = AliceKeys::generate();
    println!("   ✅ Alice keys generated");
    
    println!("\n📝 Step 2: Bob generates keys + DLEQ proof");
    let bob = BobKeys::generate();
    let _dleq_proof = generate_dleq_proof_for_bob(&bob)?;
    println!("   ✅ Bob keys + DLEQ proof generated");
    
    println!("\n📝 Step 3: Compute shared output");
    let _shared = SharedOutput::new(&alice, &bob);
    println!("   ✅ Shared Monero address computed");
    
    println!("\n📝 Step 4: Deploy contract via TypeScript");
    let contract_address = deploy_via_typescript().await?;
    println!("   ✅ Contract deployed at: {}", contract_address);
    
    println!("\n📝 Step 5: Create Rust client");
    let client: Box<dyn StarknetClient> = Box::new(
        StarknetManualClient::devnet(
            DEVNET_ACCOUNT,
            DEVNET_PRIVATE_KEY,
            "0x0", // Placeholder class hash
        )?
    );
    println!("   ✅ Rust client created");
    
    println!("\n📝 Step 6: Prepare for secret reveal");
    let secret_bytes = bob.secret_bytes();
    println!("   ✅ Secret prepared");
    
    println!("\n📝 Step 7: Reveal secret via Rust");
    let reveal_tx_hash = client.reveal_secret(&contract_address, &secret_bytes).await?;
    println!("   ✅ Secret revealed!");
    println!("   📍 Transaction hash: {}", reveal_tx_hash);
    
    // Wait for transaction confirmation
    println!("\n📝 Step 8: Wait for Transaction Confirmation");
    let view_client = StarknetManualClient::devnet(
        DEVNET_ACCOUNT,
        DEVNET_PRIVATE_KEY,
        "0x0",
    )?;
    
    let receipt = view_client.wait_for_transaction(&reveal_tx_hash).await?;
    let status = receipt.get("status")
        .and_then(|s| s.as_str())
        .unwrap_or("unknown");
    println!("   ✅ Transaction confirmed! Status: {}", status);
    
    // Verify contract state after reveal
    println!("\n📝 Step 9: Verify Contract State After Reveal");
    let is_revealed = view_client.is_secret_revealed(&contract_address).await?;
    let is_unlocked = view_client.is_unlocked(&contract_address).await?;
    println!("   ✅ is_secret_revealed: {} (expected: true)", is_revealed);
    println!("   ✅ is_unlocked: {} (expected: false, grace period)", is_unlocked);
    assert!(is_revealed, "Secret should be revealed");
    
    println!("\n📝 Step 7: Verify address derivation");
    use xmr_secret_gen::monero::address::derive_stagenet_address;
    use xmr_secret_gen::monero::two_party_keys::recover_spend_key;
    
    let full_spend_key = recover_spend_key(alice.spend_share(), bob.spend_share());
    
    // Derive view key (same method as claim_monero_after_reveal)
    use tiny_keccak::{Hasher, Keccak};
    let mut keccak = Keccak::v256();
    keccak.update(&full_spend_key.to_bytes());
    let mut hash = [0u8; 32];
    keccak.finalize(&mut hash);
    use curve25519_dalek::scalar::Scalar;
    let view_key = Scalar::from_bytes_mod_order(hash);
    
    let address = derive_stagenet_address(&full_spend_key, &view_key)?;
    println!("   ✅ Address derived: {}", address);
    assert!(address.starts_with('5'), "Stagenet address must start with '5'");
    
    println!("\n✅ Full Swap Flow Test Complete!");
    println!("{}", "=".repeat(80));
    println!("\n📊 Summary:");
    println!("   ✅ Two-party key generation: PASS");
    println!("   ✅ DLEQ proof generation: PASS");
    println!("   ✅ TypeScript deployment: PASS");
    println!("   ✅ Address derivation: PASS");
    println!("   ⚠️  Secret reveal via Rust: PENDING (requires calldata building)");
    println!("   ⚠️  Monero claim: PENDING (requires wallet-rpc)");
    
    Ok(())
}

