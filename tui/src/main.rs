//! Lumen terminal interface.
//!
//! Reads and edits the encrypted Markdown journal store (`STORE_JOURNAL`),
//! the same store the desktop app uses. Nothing is written in plaintext: the
//! store is unlocked with its passphrase for the lifetime of the process.

use clap::Parser;

use lumen_tui::cli::{run, Cli};

fn main() -> color_eyre::Result<()> {
    color_eyre::install()?;

    let cli = Cli::parse();
    run(cli)
}
