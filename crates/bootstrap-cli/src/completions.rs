use clap::CommandFactory;
use clap_complete::{Shell, generate};
use std::io::Write;

use crate::cli::{BIN_NAME, Cli, CompletionShell};

pub fn generate_bootstrap_completions(shell: CompletionShell) {
    generate_bootstrap_completions_to(shell, &mut std::io::stdout());
}

fn generate_bootstrap_completions_to(shell: CompletionShell, writer: &mut impl Write) {
    let mut command = Cli::command();
    match shell {
        CompletionShell::Bash => {
            generate(Shell::Bash, &mut command, BIN_NAME, writer);
        }
        CompletionShell::Elvish => generate(Shell::Elvish, &mut command, BIN_NAME, writer),
        CompletionShell::Fish => {
            generate(Shell::Fish, &mut command, BIN_NAME, writer);
        }
        CompletionShell::Nushell => generate(
            clap_complete_nushell::Nushell,
            &mut command,
            BIN_NAME,
            writer,
        ),
        CompletionShell::Powershell => generate(Shell::PowerShell, &mut command, BIN_NAME, writer),
        CompletionShell::Zsh => {
            generate(Shell::Zsh, &mut command, BIN_NAME, writer);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generates_all_bootstrap_completion_shells() {
        for shell in [
            CompletionShell::Bash,
            CompletionShell::Elvish,
            CompletionShell::Fish,
            CompletionShell::Nushell,
            CompletionShell::Powershell,
            CompletionShell::Zsh,
        ] {
            let mut output = Vec::new();
            generate_bootstrap_completions_to(shell, &mut output);
            assert!(!output.is_empty());
        }
    }
}
