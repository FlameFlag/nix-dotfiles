use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

/// Ways to resolve the version and download URL for an archive-backed tool.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Source {
    GithubLatest {
        repo: String,
        #[serde(default)]
        tag_prefix: String,
        asset: String,
    },
    GithubLatestMatching {
        repo: String,
        #[serde(default)]
        tag_prefix: String,
        asset_prefix: String,
        asset_suffix: String,
    },
    Direct {
        version: String,
        url: String,
    },
    Command {
        argv: Vec<String>,
        url: String,
    },
    VersionIndex {
        index_url: String,
        url: String,
    },
}
