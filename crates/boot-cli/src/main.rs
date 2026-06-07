#![cfg_attr(test, allow(clippy::expect_used, clippy::panic, clippy::unwrap_used))]

mod cli;
mod commands;
mod completions;

use clap::{Parser, error::ErrorKind};
use miette::IntoDiagnostic;

use crate::cli::Cli;

fn main() -> miette::Result<()> {
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(err) if err.kind() == ErrorKind::DisplayHelpOnMissingArgumentOrSubcommand => {
            err.print().into_diagnostic()?;
            return Ok(());
        }
        Err(err) => err.exit(),
    };
    commands::run_bootstrap_cli(cli).map_err(|err| miette::miette!("{err}"))
}
