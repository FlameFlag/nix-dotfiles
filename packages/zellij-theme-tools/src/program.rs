use std::ffi::OsString;

use clap::{Parser, ValueEnum};

use crate::{Result, btop_auto_theme, codex_zellij_theme, helix_auto_theme, zellij_auto_theme};

#[derive(Debug, Parser)]
#[command(name = "zellij-theme-run", version)]
struct Cli {
    #[arg(value_enum)]
    program: Program,
    #[arg(allow_hyphen_values = true, num_args = 0.., trailing_var_arg = true)]
    args: Vec<OsString>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, ValueEnum)]
enum Program {
    Codex,
    Btop,
    Helix,
    Zellij,
}

impl Program {
    fn run(self, args: Vec<OsString>) -> Result<i32> {
        match self {
            Self::Codex => codex_zellij_theme::run_with_args(args),
            Self::Btop => btop_auto_theme::run_with_args(args),
            Self::Helix => helix_auto_theme::run_with_args(args),
            Self::Zellij => zellij_auto_theme::run_with_args(args),
        }
    }
}

/// Runs `zellij-theme-run`.
///
/// # Errors
///
/// Returns an error if the requested program profile is missing, unknown, or
/// cannot prepare and execute its command.
pub fn run() -> Result<i32> {
    let cli = match Cli::try_parse() {
        Ok(cli) => cli,
        Err(err) => {
            err.print()?;
            return Ok(err.exit_code());
        }
    };
    cli.program.run(cli.args)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_profile_names() {
        assert_eq!(
            Cli::try_parse_from(["zellij-theme-run", "codex"])
                .expect("codex profile should parse")
                .program,
            Program::Codex
        );
        assert_eq!(
            Cli::try_parse_from(["zellij-theme-run", "btop"])
                .expect("btop profile should parse")
                .program,
            Program::Btop
        );
        assert_eq!(
            Cli::try_parse_from(["zellij-theme-run", "helix"])
                .expect("helix profile should parse")
                .program,
            Program::Helix
        );
        assert_eq!(
            Cli::try_parse_from(["zellij-theme-run", "zellij"])
                .expect("zellij profile should parse")
                .program,
            Program::Zellij
        );
    }

    #[test]
    fn keeps_hyphenated_program_arguments() {
        let cli = Cli::try_parse_from([
            "zellij-theme-run",
            "codex",
            "--dangerously-bypass-approvals-and-sandbox",
            "--ask-for-approval",
            "never",
        ])
        .expect("hyphenated program args should pass through");

        assert_eq!(cli.program, Program::Codex);
        assert_eq!(
            cli.args,
            [
                OsString::from("--dangerously-bypass-approvals-and-sandbox"),
                OsString::from("--ask-for-approval"),
                OsString::from("never"),
            ]
        );
    }
}
