//! Generate single DLEQ vector with complete Cairo deployment data.
//!
//! By default this keeps the historical deterministic test vector. For live
//! deployments pass `--random`; write that output only to a private path.

use anyhow::{anyhow, Context, Result};
use clap::Parser;
use curve25519_dalek::constants::ED25519_BASEPOINT_POINT;
use curve25519_dalek::scalar::Scalar;
use rand::rngs::OsRng;
use rand::RngCore;
use serde_json::json;
use sha2::{Digest, Sha256};
use std::fs;
use std::path::PathBuf;
use xmr_secret_gen::dleq::generate_dleq_proof;
use zeroize::Zeroizing;

#[derive(Parser, Debug)]
struct Args {
    /// Generate a fresh random vector instead of the deterministic test vector.
    #[arg(long)]
    random: bool,

    /// Use this 32-byte hex secret instead of generating one.
    #[arg(long)]
    secret_hex: Option<String>,

    /// Write JSON to this path instead of stdout.
    #[arg(long)]
    output: Option<PathBuf>,
}

fn main() -> Result<()> {
    let args = Args::parse();
    if args.random && args.secret_hex.is_some() {
        return Err(anyhow!("use either --random or --secret-hex, not both"));
    }

    let secret_bytes = if let Some(secret_hex) = args.secret_hex.as_deref() {
        parse_32_byte_hex(secret_hex)?
    } else if args.random {
        random_secret_bytes()
    } else {
        // Historical deterministic test vector for reproducibility.
        [0x12u8; 32]
    };

    let secret = Scalar::from_bytes_mod_order(secret_bytes);
    let secret_zeroizing = Zeroizing::new(secret);

    // Generate hashlock H = SHA-256(raw_secret_bytes)
    // CRITICAL: Cairo uses SHA-256(raw_secret_bytes) in verify_and_unlock
    // So the hashlock must match: SHA-256(secret_bytes), not SHA-256(scalar.to_bytes())
    let hashlock: [u8; 32] = Sha256::digest(secret_bytes).into();

    // Generate adaptor point T = t·G
    let adaptor_point = ED25519_BASEPOINT_POINT * *secret_zeroizing;

    // Generate DLEQ proof (uses raw bytes hashlock to match Cairo)
    let proof = generate_dleq_proof(&secret_zeroizing, &secret_bytes, &adaptor_point, &hashlock)
        .expect("Proof generation should succeed for valid inputs");

    // Convert to Cairo format (includes compressed points and sqrt hints)
    let cairo_format = proof
        .to_cairo_format(&adaptor_point)
        .expect("Failed to derive Cairo sqrt hints");

    // Create complete test vector JSON
    let output = json!({
        "description": "Complete DLEQ proof test vector for deployment",
        "secret": hex::encode(secret_bytes),
        "hashlock": hex::encode(hashlock),
        "adaptor_point_compressed": hex::encode(cairo_format.adaptor_point_compressed),
        "adaptor_point_sqrt_hint": hex::encode(cairo_format.adaptor_point_sqrt_hint),
        "dleq_second_point_compressed": hex::encode(cairo_format.second_point_compressed),
        "second_point_compressed": hex::encode(cairo_format.second_point_compressed),
        "second_point_sqrt_hint": hex::encode(cairo_format.second_point_sqrt_hint),
        "challenge": hex::encode(cairo_format.challenge),
        "response": hex::encode(cairo_format.response),
        "g_compressed": hex::encode(cairo_format.g_compressed),
        "y_compressed": hex::encode(cairo_format.y_compressed),
        "r1_compressed": hex::encode(cairo_format.r1_compressed),
        "r1_sqrt_hint": hex::encode(cairo_format.r1_sqrt_hint),
        "r2_compressed": hex::encode(cairo_format.r2_compressed),
        "r2_sqrt_hint": hex::encode(cairo_format.r2_sqrt_hint),
        "expected_verification": true,
        "notes": "Complete vector with all DLEQ proof data needed for deployment"
    });

    let encoded = serde_json::to_string_pretty(&output)? + "\n";
    if let Some(path) = args.output {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
        fs::write(&path, encoded).with_context(|| format!("failed to write {}", path.display()))?;
    } else {
        print!("{}", encoded);
    }

    Ok(())
}

fn parse_32_byte_hex(value: &str) -> Result<[u8; 32]> {
    let clean = value.strip_prefix("0x").unwrap_or(value);
    let bytes = hex::decode(clean).context("invalid --secret-hex")?;
    if bytes.len() != 32 {
        return Err(anyhow!(
            "--secret-hex must be 32 bytes, got {}",
            bytes.len()
        ));
    }
    let mut out = [0u8; 32];
    out.copy_from_slice(&bytes);
    Ok(out)
}

fn random_secret_bytes() -> [u8; 32] {
    loop {
        let mut raw = [0u8; 32];
        OsRng.fill_bytes(&mut raw);
        let scalar = Scalar::from_bytes_mod_order(raw);
        if scalar != Scalar::ZERO {
            return scalar.to_bytes();
        }
    }
}
