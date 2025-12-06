//! Monero Atomic Swap - Secret Generator CLI.
//!
//! Generates a Monero-compatible scalar and its SHA-256 hash formatted for
//! consumption by the Cairo AtomicLock contract/tests.

use clap::Parser;
use xmr_secret_gen::{generate_swap_secret, SwapSecret};

/// CLI arguments.
#[derive(Parser, Debug)]
#[command(name = "xmr-secret-gen")]
#[command(about = "Generate Monero scalar + SHA-256 hash for atomic swaps")]
struct Args {
    /// Output format: "human" or "json".
    #[arg(short, long, default_value = "human")]
    format: String,
}

fn main() {
    let args = Args::parse();
    let secret = generate_swap_secret();
    match args.format.as_str() {
        "json" => print_json(&secret),
        _ => print_human_readable(&secret),
    }
}

fn print_json(secret: &SwapSecret) {
    println!("{}", serde_json::to_string_pretty(secret).expect("serialize"));
}

fn print_human_readable(secret: &SwapSecret) {
    println!("[1] SECRET SCALAR (save securely)");
    println!("    hex: {}\n", secret.secret_hex);
    println!("[2] CAIRO HASH");
    println!("    let expected_hash = {};\n", secret.cairo_hash_literal);
    println!("[3] CAIRO SECRET");
    println!("    let secret_input = {};", secret.cairo_secret_literal);
}
