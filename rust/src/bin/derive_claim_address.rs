//! Derive the Monero address controlled by a partial spend key plus a revealed secret.
//!
//! This is an ops helper for stagenet rehearsals: fund the derived address,
//! then `claim_revealed_secrets` should recover the same full spend key and
//! sweep the output through wallet-rpc.

use anyhow::{anyhow, Context, Result};
use clap::Parser;
use curve25519_dalek::scalar::Scalar;
use monero::Network;
use rand::rngs::OsRng;
use rand::RngCore;
use serde_json::json;
use sha2::{Digest, Sha256};
use tiny_keccak::{Hasher, Keccak};
use zeroize::Zeroize;

use xmr_secret_gen::monero::address::derive_address_for_network;

#[derive(Parser, Debug)]
#[command(name = "derive_claim_address")]
#[command(about = "Derive Monero claim address from partial key plus revealed secret")]
struct Args {
    /// Revealed Starknet secret as 32-byte hex.
    #[arg(long)]
    secret_hex: String,

    /// Optional partial spend-key share as 32-byte hex. Random if omitted.
    #[arg(long)]
    partial_spend_key_hex: Option<String>,

    /// Monero network: mainnet, stagenet, or testnet.
    #[arg(long, default_value = "stagenet")]
    monero_network: String,

    /// Include derived full spend/view keys in output. Only useful for debugging.
    #[arg(long)]
    include_derived_private: bool,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let mut secret = parse_32_byte_hex(&args.secret_hex, "secret")?;
    let partial = match &args.partial_spend_key_hex {
        Some(value) => parse_32_byte_hex(value, "partial spend key")?,
        None => random_scalar_bytes(),
    };

    let secret_scalar = Scalar::from_bytes_mod_order(secret);
    let partial_scalar = Scalar::from_bytes_mod_order(partial);
    let full_spend_key = partial_scalar + secret_scalar;
    let mut view_key = derive_view_key(&full_spend_key);
    let network = parse_network(&args.monero_network)?;
    let address = derive_address_for_network(&full_spend_key, &view_key, network)
        .context("Failed to derive Monero address")?;

    let secret_hash: [u8; 32] = Sha256::digest(secret).into();
    let secret_hash_first_word = u32::from_be_bytes([
        secret_hash[0],
        secret_hash[1],
        secret_hash[2],
        secret_hash[3],
    ]);

    let mut output = json!({
        "network": args.monero_network,
        "address": address,
        "partial_spend_key_hex": hex::encode(partial),
        "secret_hash_first_word": format!("0x{:x}", secret_hash_first_word),
    });

    if args.include_derived_private {
        output["full_spend_key_hex"] = json!(hex::encode(full_spend_key.to_bytes()));
        output["view_key_hex"] = json!(hex::encode(view_key.to_bytes()));
    }

    secret.zeroize();
    view_key.zeroize();

    println!("{}", serde_json::to_string_pretty(&output)?);
    Ok(())
}

fn parse_32_byte_hex(value: &str, label: &str) -> Result<[u8; 32]> {
    let hex_value = value.strip_prefix("0x").unwrap_or(value);
    let mut bytes = hex::decode(hex_value).with_context(|| format!("Invalid {} hex", label))?;
    if bytes.len() != 32 {
        bytes.zeroize();
        return Err(anyhow!("{} must be 32 bytes, got {}", label, bytes.len()));
    }
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    bytes.zeroize();
    Ok(out)
}

fn random_scalar_bytes() -> [u8; 32] {
    let mut raw = [0u8; 32];
    OsRng.fill_bytes(&mut raw);
    Scalar::from_bytes_mod_order(raw).to_bytes()
}

fn derive_view_key(spend_key: &Scalar) -> Scalar {
    let mut keccak = Keccak::v256();
    keccak.update(&spend_key.to_bytes());
    let mut hash = [0u8; 32];
    keccak.finalize(&mut hash);
    Scalar::from_bytes_mod_order(hash)
}

fn parse_network(network: &str) -> Result<Network> {
    match network.trim().to_ascii_lowercase().as_str() {
        "mainnet" | "main" => Ok(Network::Mainnet),
        "stagenet" | "stage" => Ok(Network::Stagenet),
        "testnet" | "test" => Ok(Network::Testnet),
        value => Err(anyhow!("Unsupported Monero network: {}", value)),
    }
}
