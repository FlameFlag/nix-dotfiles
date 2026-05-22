mod cli;
mod commands;
mod completions;

use clap::{CommandFactory, Parser};

use crate::cli::Cli;

fn main() -> commands::Result<()> {
    if std::env::args_os().len() == 1 {
        Cli::command().print_help()?;
        println!();
        return Ok(());
    }

    commands::run_bootstrap_cli(Cli::parse())
}
