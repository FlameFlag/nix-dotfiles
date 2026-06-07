use dotfiles_common::http::Client;
use serde::Deserialize;

use crate::error::{Error, Result};

#[derive(Debug, Deserialize)]
struct GithubReleaseResponse {
    tag_name: String,
}

pub fn latest_tag(repo: &str) -> Result<String> {
    eprintln!("info: Fetching latest {repo} release...");
    let (owner, name) = repo
        .split_once('/')
        .ok_or_else(|| Error::CommandFailed(format!("invalid GitHub repo: {repo}")))?;
    let client = Client::new("nix-dotfiles-chezmoi-support")?;
    let release: GithubReleaseResponse = client.json(&format!(
        "https://api.github.com/repos/{owner}/{name}/releases/latest"
    ))?;
    Ok(release.tag_name)
}
