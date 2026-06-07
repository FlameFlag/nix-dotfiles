use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::catalog::{ArchiveKind, Link};
use crate::platform::Predicate;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct BuildAction {
    /// Repository-relative build directory.
    pub path: String,
    /// Build command; supports `{{ repo_dir }}`, `{{ build_dir }}`, `{{ prefix }}`, and `{{ tool }}`.
    #[serde(default)]
    #[garde(length(min = 1))]
    pub argv: Vec<String>,
    /// Explicit links from `{prefix}`; empty means `bin/<tool bin>`.
    #[serde(default)]
    #[garde(dive)]
    pub links: Vec<Link>,
}

impl BuildAction {
    pub(super) fn apply_defaults(&mut self) {
        if self.argv.is_empty() {
            self.argv = default_cargo_install_argv();
        }
    }
}

fn default_cargo_install_argv() -> Vec<String> {
    [
        "cargo",
        "install",
        "--path",
        "{{ build_dir }}",
        "--root",
        "{{ prefix }}",
        "--force",
        "--locked",
    ]
    .map(str::to_owned)
    .to_vec()
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct SourceBuildAction {
    #[garde(length(min = 1))]
    pub version: String,
    #[serde(default)]
    pub kind: Option<ArchiveKind>,
    #[serde(default)]
    pub strip_components: Option<usize>,
    #[serde(default)]
    pub argv: Vec<String>,
    #[serde(default)]
    pub sandbox_home: bool,
    #[serde(default)]
    pub links: Vec<Link>,
    #[garde(length(min = 1), dive)]
    pub platforms: Vec<SourceBuildPlatform>,
}

impl SourceBuildAction {
    #[must_use]
    pub fn platform_kind(&self, platform: &SourceBuildPlatform) -> Option<ArchiveKind> {
        platform
            .kind
            .or(self.kind)
            .or_else(|| ArchiveKind::from_path(&platform.archive_file))
            .or_else(|| ArchiveKind::from_path(&platform.url))
    }

    #[must_use]
    pub fn platform_strip_components(&self, platform: &SourceBuildPlatform) -> usize {
        platform
            .strip_components
            .or(self.strip_components)
            .unwrap_or(0)
    }

    #[must_use]
    pub fn platform_argv<'a>(&'a self, platform: &'a SourceBuildPlatform) -> &'a [String] {
        platform.argv.as_deref().unwrap_or(&self.argv)
    }

    #[must_use]
    pub fn platform_sandbox_home(&self, platform: &SourceBuildPlatform) -> bool {
        platform.sandbox_home.unwrap_or(self.sandbox_home)
    }

    #[must_use]
    pub fn platform_links<'a>(&'a self, platform: &'a SourceBuildPlatform) -> &'a [Link] {
        if platform.links.is_empty() {
            &self.links
        } else {
            &platform.links
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct SourceBuildPlatform {
    pub when: Predicate,
    /// Template value exposed as `{{ platform }}` in source URLs and link paths.
    #[garde(length(min = 1))]
    pub platform: String,
    #[garde(length(min = 1))]
    pub url: String,
    /// File name to use for the downloaded source archive.
    pub archive_file: String,
    #[serde(default)]
    pub kind: Option<ArchiveKind>,
    #[serde(default)]
    pub strip_components: Option<usize>,
    /// Optional build command run from the extracted source directory.
    ///
    /// If this is empty, the extracted source tree is installed directly.
    #[serde(default)]
    pub argv: Option<Vec<String>>,
    /// Whether to run the build command with an isolated fake home/cache.
    #[serde(default)]
    pub sandbox_home: Option<bool>,
    #[serde(default)]
    #[garde(dive)]
    pub links: Vec<Link>,
}
