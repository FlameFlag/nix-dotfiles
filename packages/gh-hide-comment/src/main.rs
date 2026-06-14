#![cfg_attr(test, allow(clippy::expect_used, clippy::panic, clippy::unwrap_used))]

mod auth;
mod cli;
mod comment_url;
mod error;
mod github;

use clap::Parser;
use dotfiles_common::http::Client;
use std::io::Write;

use crate::auth::token;
use crate::cli::Cli;
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
    let client = Client::new("gh-hide-comment")?;

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
