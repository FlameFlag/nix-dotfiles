#![cfg_attr(test, allow(clippy::expect_used, clippy::panic, clippy::unwrap_used))]

mod command;
mod context;
mod error;
mod fs;
mod github;
mod hyper_window_tiling;
mod raycast;
mod shell;
mod vscode;
mod yazi;
mod zed;

use clap::{Args, Parser, Subcommand, ValueHint};
use std::path::PathBuf;

use crate::context::Options;
use crate::error::Result;

#[derive(Debug, Parser)]
#[command(
    name = "chezmoi-support",
    about = "Runtime helpers for dotfiles chezmoi hooks",
    version
)]
struct Cli {
    #[command(flatten)]
    global: GlobalArgs,
    #[command(subcommand)]
    command: CommandName,
}

#[derive(Debug, Clone, Args)]
#[command(next_help_heading = "Global Options")]
struct GlobalArgs {
    /// Chezmoi source directory.
    #[arg(
        long,
        global = true,
        env = "CHEZMOI_SOURCE_DIR",
        value_name = "DIR",
        value_hint = ValueHint::DirPath
    )]
    source_dir: Option<PathBuf>,

    /// Home directory used by chezmoi.
    #[arg(
        long,
        global = true,
        env = "CHEZMOI_HOME_DIR",
        value_name = "DIR",
        value_hint = ValueHint::DirPath
    )]
    home_dir: Option<PathBuf>,

    /// Chezmoi OS name.
    #[arg(long, global = true, env = "CHEZMOI_OS", value_name = "OS")]
    os: Option<String>,
}

#[derive(Debug, Clone, Copy, Subcommand)]
enum CommandName {
    NushellInit,
    ShellInit,
    InstallVsExtensions,
    InstallHyperWindowTiling,
    ZedInstallCatppuccinTheme,
    YaziInit,
    RaycastBetaPatch,
}

fn main() -> miette::Result<()> {
    let cli = Cli::parse();
    run_chezmoi_support(cli.command, cli.global.into())?;
    Ok(())
}

fn run_chezmoi_support(command: CommandName, options: Options) -> Result<()> {
    match command {
        CommandName::NushellInit => shell::nushell_init(),
        CommandName::ShellInit => shell::shell_init(),
        CommandName::InstallVsExtensions => vscode::install_vs_extensions(&options),
        CommandName::InstallHyperWindowTiling => {
            hyper_window_tiling::install_hyper_window_tiling(&options)
        }
        CommandName::ZedInstallCatppuccinTheme => zed::install_catppuccin_theme(&options),
        CommandName::YaziInit => yazi::install_plugins(&options),
        CommandName::RaycastBetaPatch => raycast::patch_beta_user(&options),
    }
}

impl From<GlobalArgs> for Options {
    fn from(args: GlobalArgs) -> Self {
        Self {
            home_dir: args.home_dir,
            source_dir: args.source_dir,
            os: args.os,
        }
    }
}
