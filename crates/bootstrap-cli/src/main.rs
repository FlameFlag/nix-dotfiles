#![cfg_attr(test, allow(clippy::expect_used, clippy::panic, clippy::unwrap_used))]

mod cli;
mod commands;
mod completions;

use clap::{CommandFactory, Parser};
use miette::IntoDiagnostic;

use crate::cli::Cli;

fn main() -> miette::Result<()> {
    if std::env::args_os().len() == 1 {
        Cli::command().print_help().into_diagnostic()?;
        println!();
        return Ok(());
    }

    commands::run_bootstrap_cli(Cli::parse()).map_err(|err| miette::miette!("{err}"))
}
