//! `lumen-lsp` binary entry point.
//!
//! Unlocks the vault from environment variables, then runs the LSP server
//! on stdin/stdout.
//!
//! Usage:
//!   LUMEN_VAULT=/path/to/journal LUMEN_PASSWORD=secret lumen-lsp

use std::env;
use std::path::PathBuf;

use clap::Parser;

use lumen_core::vault::{self, STORE_JOURNAL};
use lumen_core::lsp::server;

/// Language Server Protocol server for Lumen.
///
/// Provides editor integration for VS Code, Neovim, Helix, Zed, etc.
#[derive(Parser)]
#[command(name = "lumen-lsp")]
#[command(about = "Lumen Markdown Language Server")]
struct Cli {
    /// Path to the Lumen vault directory.
    #[arg(long, env = "LUMEN_VAULT")]
    vault: Option<PathBuf>,

    /// Passphrase to unlock the vault.
    #[arg(long, env = "LUMEN_PASSWORD")]
    password: Option<String>,
}

#[tokio::main]
async fn main() {
    let cli = Cli::parse();

    let vault_path = cli
        .vault
        .unwrap_or_else(|| PathBuf::from("."));
    let password = cli.password.unwrap_or_default();

    if let Err(e) = vault::unlock(
        vault_path.to_str().unwrap_or("."),
        &password,
        STORE_JOURNAL,
    ) {
        eprintln!("Failed to unlock vault: {e}");
        std::process::exit(1);
    }

    server::run().await;
}
