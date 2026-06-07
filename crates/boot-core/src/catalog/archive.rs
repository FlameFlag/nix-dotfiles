use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::catalog::{Link, Source};
use crate::platform::Predicate;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct ArchiveAction {
    /// Default source for platforms that do not override it.
    pub source: Option<Source>,
    /// Default archive format for platforms that do not override it.
    #[serde(default)]
    pub kind: Option<ArchiveKind>,
    /// Default leading archive path components to discard during extraction.
    #[serde(default)]
    pub strip_components: Option<usize>,
    /// Default files to link into the managed binary directory.
    #[serde(default)]
    pub links: Vec<Link>,
    /// Default macOS application bundles to symlink into `/Applications`.
    #[serde(default)]
    pub app_links: Vec<Link>,
    /// Host-specific archive format, source, and link layout.
    #[garde(length(min = 1), dive)]
    pub platforms: Vec<ArchivePlatform>,
}

impl ArchiveAction {
    #[must_use]
    pub fn platform_kind(&self, platform: &ArchivePlatform) -> Option<ArchiveKind> {
        platform
            .kind
            .or(self.kind)
            .or_else(|| ArchiveKind::from_path(&platform.platform))
    }

    #[must_use]
    pub fn platform_strip_components(&self, platform: &ArchivePlatform) -> usize {
        platform
            .strip_components
            .or(self.strip_components)
            .unwrap_or(0)
    }

    #[must_use]
    pub fn platform_links<'a>(&'a self, platform: &'a ArchivePlatform) -> &'a [Link] {
        if platform.links.is_empty() {
            &self.links
        } else {
            &platform.links
        }
    }

    #[must_use]
    pub fn platform_app_links<'a>(&'a self, platform: &'a ArchivePlatform) -> &'a [Link] {
        if platform.app_links.is_empty() {
            &self.app_links
        } else {
            &platform.app_links
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct FileAction {
    /// Source used to resolve the file download URL and version.
    pub source: Source,
    /// File name to write under the managed install root.
    pub file: String,
    /// Files to link into the managed binary directory.
    #[garde(length(min = 1), dive)]
    pub links: Vec<Link>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct ArchivePlatform {
    pub when: Predicate,
    /// Template value exposed as `{{ platform }}` in source URLs and link paths.
    #[garde(length(min = 1))]
    pub platform: String,
    /// Per-platform source override.
    pub source: Option<Source>,
    #[serde(default)]
    pub kind: Option<ArchiveKind>,
    /// Leading archive path components to discard during extraction.
    #[serde(default)]
    pub strip_components: Option<usize>,
    /// Files to link into the managed binary directory.
    #[serde(default)]
    #[garde(dive)]
    pub links: Vec<Link>,
    /// macOS application bundles to symlink into `/Applications`.
    #[serde(default)]
    #[garde(dive)]
    pub app_links: Vec<Link>,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum ArchiveKind {
    TarXz,
    TarGz,
    Zip,
}

impl ArchiveKind {
    #[must_use]
    pub fn from_path(path: &str) -> Option<Self> {
        match path {
            path if path.ends_with(".tar.xz") || path.ends_with(".txz") => Some(Self::TarXz),
            path if path.ends_with(".tar.gz") || path.ends_with(".tgz") => Some(Self::TarGz),
            path if path.ends_with(".zip") => Some(Self::Zip),
            _ => None,
        }
    }
}
