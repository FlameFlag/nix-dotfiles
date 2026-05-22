mod auth;
mod cli;
mod comment_url;
mod error;
mod github;

use clap::{CommandFactory, Parser};
use clap_complete::generate;
use reqwest::blocking::Client;
use std::io::Write;

use crate::auth::token;
use crate::cli::{Cli, CompletionShell};
use crate::error::Result;
use crate::github::hide;

fn main() {
    let cli = Cli::parse();
    match run_gh_hide_comment(cli) {
        Ok(code) => std::process::exit(code),
        Err(err) => {
            eprintln!("error: {err}");
            std::process::exit(1);
        }
    }
}

fn run_gh_hide_comment(mut cli: Cli) -> Result<i32> {
    if let Some(shell) = cli.completions {
        generate_gh_hide_comment_completions(shell);
        return Ok(0);
    }

    if cli.urls.is_empty() {
        eprintln!("info: Interactive mode. Paste comment URLs, blank line to quit.");
        loop {
            eprint!("url: ");
            std::io::stderr().flush()?;
            let mut url = String::new();
            std::io::stdin().read_line(&mut url)?;
            let trimmed = url.trim();
            if trimmed.is_empty() {
                break;
            }
            cli.urls.push(trimmed.to_owned());
        }
    }

    let token = token()?;
    let _ = rustls::crypto::ring::default_provider().install_default();
    let client = Client::builder().user_agent("gh-hide-comment").build()?;

    let mut hidden = 0_usize;
    for comment_url in &cli.urls {
        eprintln!("info: Processing {comment_url}");
        match hide(&client, &token, comment_url, cli.reason) {
            Ok(reason) => {
                hidden += 1;
                eprintln!("success: {comment_url}: hidden as {reason}");
            }
            Err(err) => eprintln!("error: {comment_url}: {err}"),
        }
    }

    eprintln!("info: Done. {hidden}/{} hidden.", cli.urls.len());
    if hidden == cli.urls.len() {
        Ok(0)
    } else {
        eprintln!(
            "error: {} of {} failed",
            cli.urls.len() - hidden,
            cli.urls.len()
        );
        Ok(1)
    }
}

fn generate_gh_hide_comment_completions(shell: CompletionShell) {
    generate_gh_hide_comment_completions_to(shell, &mut std::io::stdout());
}

fn generate_gh_hide_comment_completions_to(shell: CompletionShell, writer: &mut impl Write) {
    let mut command = Cli::command();
    match shell {
        CompletionShell::Bash => {
            generate(
                clap_complete::Shell::Bash,
                &mut command,
                "gh-hide-comment",
                writer,
            );
        }
        CompletionShell::Elvish => {
            generate(
                clap_complete::Shell::Elvish,
                &mut command,
                "gh-hide-comment",
                writer,
            );
        }
        CompletionShell::Fish => {
            generate(
                clap_complete::Shell::Fish,
                &mut command,
                "gh-hide-comment",
                writer,
            );
        }
        CompletionShell::Nushell => {
            generate(
                clap_complete_nushell::Nushell,
                &mut command,
                "gh-hide-comment",
                writer,
            );
        }
        CompletionShell::Powershell => {
            generate(
                clap_complete::Shell::PowerShell,
                &mut command,
                "gh-hide-comment",
                writer,
            );
        }
        CompletionShell::Zsh => {
            generate(
                clap_complete::Shell::Zsh,
                &mut command,
                "gh-hide-comment",
                writer,
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generates_all_gh_hide_comment_completion_shells() {
        for shell in [
            CompletionShell::Bash,
            CompletionShell::Elvish,
            CompletionShell::Fish,
            CompletionShell::Nushell,
            CompletionShell::Powershell,
            CompletionShell::Zsh,
        ] {
            let mut output = Vec::new();
            generate_gh_hide_comment_completions_to(shell, &mut output);
            assert!(!output.is_empty());
        }
    }
}
