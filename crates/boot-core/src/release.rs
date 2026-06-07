use dotfiles_common::http::Client;
use serde::Deserialize;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ReleaseError {
    #[error(transparent)]
    Http(#[from] dotfiles_common::http::HttpError),
    #[error("invalid GitHub repository, expected owner/name")]
    InvalidRepo,
    #[error("asset not found")]
    AssetNotFound,
}

#[derive(Debug)]
pub struct GithubRelease {
    tag_name: String,
    assets: Vec<GithubAsset>,
}

#[derive(Debug)]
struct GithubAsset {
    name: String,
    browser_download_url: String,
}

#[derive(Debug, Deserialize)]
struct GithubReleaseResponse {
    tag_name: String,
    assets: Vec<GithubAssetResponse>,
}

#[derive(Debug, Deserialize)]
struct GithubAssetResponse {
    name: String,
    browser_download_url: String,
}

impl GithubRelease {
    /// Fetches the latest GitHub release for `repo`.
    ///
    /// # Errors
    ///
    /// Returns an error if the GitHub request or response decoding fails.
    pub fn latest(repo: &str) -> Result<Self, ReleaseError> {
        let (owner, name) = repo.split_once('/').ok_or(ReleaseError::InvalidRepo)?;
        let client = Client::new("dotfiles-bootstrap")?;
        let release: GithubReleaseResponse = client.json(&format!(
            "https://api.github.com/repos/{owner}/{name}/releases/latest"
        ))?;
        Ok(Self {
            tag_name: release.tag_name,
            assets: release
                .assets
                .into_iter()
                .map(|asset| GithubAsset {
                    name: asset.name,
                    browser_download_url: asset.browser_download_url,
                })
                .collect(),
        })
    }

    #[must_use]
    pub fn version(&self, tag_prefix: &str) -> String {
        self.tag_name
            .strip_prefix(tag_prefix)
            .unwrap_or(&self.tag_name)
            .to_owned()
    }

    /// Finds an asset URL by exact asset name.
    ///
    /// # Errors
    ///
    /// Returns an error if no matching asset exists.
    pub fn asset_url(&self, name: &str) -> Result<String, ReleaseError> {
        self.assets
            .iter()
            .find(|asset| asset.name == name)
            .map(|asset| asset.browser_download_url.clone())
            .ok_or(ReleaseError::AssetNotFound)
    }

    /// Finds an asset URL by prefix and suffix.
    ///
    /// # Errors
    ///
    /// Returns an error if no matching asset exists.
    pub fn matching_asset_url(&self, prefix: &str, suffix: &str) -> Result<String, ReleaseError> {
        self.assets
            .iter()
            .find(|asset| asset.name.starts_with(prefix) && asset.name.ends_with(suffix))
            .map(|asset| asset.browser_download_url.clone())
            .ok_or(ReleaseError::AssetNotFound)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn version_trims_prefix() {
        let release = GithubRelease {
            tag_name: "v1.2.3".into(),
            assets: vec![],
        };
        assert_eq!(release.version("v"), "1.2.3");
        assert_eq!(release.version("tool-"), "v1.2.3");
    }
}
