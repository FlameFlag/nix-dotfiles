use clap::CommandFactory;
use clap_complete_command::Shell;
use std::io::Write;

use crate::cli::Cli;

pub fn generate_bootstrap_completions(shell: Shell) {
    generate_bootstrap_completions_to(shell, &mut std::io::stdout());
}

fn generate_bootstrap_completions_to(shell: Shell, writer: &mut impl Write) {
    let mut command = Cli::command();
    shell.generate(&mut command, writer);
}

#[cfg(test)]
mod tests {
    use super::*;
    use clap::ValueEnum;

    #[test]
    fn generates_all_bootstrap_completion_shells() {
        for &shell in Shell::value_variants() {
            let mut output = Vec::new();
            generate_bootstrap_completions_to(shell, &mut output);
            assert!(!output.is_empty());
        }
    }
}
