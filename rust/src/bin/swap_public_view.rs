//! Render a sanitized frontend/API view from SwapTerms + SwapState JSON.

use anyhow::{Context, Result};
use clap::Parser;
use std::path::PathBuf;
use xmr_secret_gen::swap::{SwapPublicView, SwapState, SwapTerms};

#[derive(Debug, Parser)]
#[command(name = "swap_public_view")]
#[command(about = "Render the public UI/API view for a swap")]
struct Args {
    /// Path to a SwapTerms JSON file.
    #[arg(long)]
    terms_json: PathBuf,

    /// Path to a SwapState JSON file.
    #[arg(long)]
    state_json: PathBuf,

    /// Optional current Starknet timestamp for claimability decisions.
    #[arg(long)]
    now: Option<u64>,
}

fn main() -> Result<()> {
    let args = Args::parse();
    let terms: SwapTerms = read_json(&args.terms_json).context("failed to read SwapTerms JSON")?;
    let state: SwapState = read_json(&args.state_json).context("failed to read SwapState JSON")?;
    let view = SwapPublicView::from_terms_state_at(&terms, &state, args.now)?;
    println!("{}", serde_json::to_string_pretty(&view)?);
    Ok(())
}

fn read_json<T: serde::de::DeserializeOwned>(path: &PathBuf) -> Result<T> {
    let bytes =
        std::fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_slice(&bytes).with_context(|| format!("failed to parse {}", path.display()))
}
