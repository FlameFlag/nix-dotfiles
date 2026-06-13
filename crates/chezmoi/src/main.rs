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

use clap::{Args, CommandFactory, Parser, Subcommand, ValueHint};
use clap_complete_command::Shell;
use std::io::Write;
use std::path::PathBuf;

use crate::context::Options;
use crate::context::context_with_options;
use crate::error::Result;
use dotfiles_common::fs::write_text_if_changed;

const STATIC_COMPLETION_PATHS: &[StaticCompletionPath] = &[
    StaticCompletionPath {
        shell: Shell::Nu,
        path: "dot_config/nushell/completions/chezmoi-support.nu",
    },
    StaticCompletionPath {
        shell: Shell::Nu,
        path: "Library/Application Support/nushell/completions/chezmoi-support.nu",
    },
];

#[derive(Debug, Clone, Copy)]
struct StaticCompletionPath {
    shell: Shell,
    path: &'static str,
}

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
    SyncCompletions,
    Completions { shell: Shell },
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
        CommandName::SyncCompletions => sync_completions(&options),
        CommandName::Completions { shell } => {
            generate_chezmoi_support_completions(shell);
            Ok(())
        }
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

fn generate_chezmoi_support_completions(shell: Shell) {
    generate_chezmoi_support_completions_to(shell, &mut std::io::stdout());
}

fn sync_completions(options: &Options) -> Result<()> {
    let ctx = context_with_options(options)?;
    for completion in STATIC_COMPLETION_PATHS {
        write_text_if_changed(
            ctx.source_dir.join(completion.path),
            &generated_completions(completion.shell),
        )?;
    }
    Ok(())
}

fn generated_completions(shell: Shell) -> String {
    let mut output = Vec::new();
    generate_chezmoi_support_completions_to(shell, &mut output);
    String::from_utf8_lossy(&output).into_owned()
}

fn generate_chezmoi_support_completions_to(shell: Shell, writer: &mut impl Write) {
    let mut command = Cli::command();
    shell.generate(&mut command, writer);
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::error::Error;
    use clap::ValueEnum;
    use std::path::Path;

    #[test]
    fn generates_all_chezmoi_support_completion_shells() {
        for &shell in Shell::value_variants() {
            let mut output = Vec::new();
            generate_chezmoi_support_completions_to(shell, &mut output);
            assert!(!output.is_empty());
        }
    }

    #[test]
    fn checked_in_nushell_completions_match_generated_output() -> Result<()> {
        let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
        let source_dir = manifest_dir
            .parent()
            .and_then(Path::parent)
            .map(|repo| repo.join("dotfiles"))
            .ok_or_else(|| Error::CommandFailed("could not find repository root".into()))?;
        let generated = generated_completions(Shell::Nu);

        for completion in STATIC_COMPLETION_PATHS {
            assert!(matches!(completion.shell, Shell::Nu));
            let path = source_dir.join(completion.path);
            assert_eq!(fs_err::read_to_string(path)?, generated);
        }
        Ok(())
    }
}
