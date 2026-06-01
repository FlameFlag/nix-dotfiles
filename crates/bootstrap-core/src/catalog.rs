use std::path::Path;

use fs_err as fs;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::platform::{Host, HostOs, HostRequirement, Predicate, meets_requirement};

#[cfg(test)]
mod tests;
mod validation;

#[derive(Debug, Error)]
pub enum CatalogError {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Toml(#[from] toml::de::Error),
    #[error("manifest: {0}")]
    Invalid(String),
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
pub struct Catalog {
    #[garde(length(min = 1), dive)]
    pub tools: Vec<Tool>,
}

impl Catalog {
    /// Loads and validates a catalog from TOML.
    ///
    /// # Errors
    ///
    /// Returns an error if reading, parsing, deserializing, or validation fails.
    pub fn load(path: impl AsRef<Path>) -> Result<Self, CatalogError> {
        let text = fs::read_to_string(path)?;
        let deserializer = toml::Deserializer::parse(&text)?;
        let catalog: Self = serde_path_to_error::deserialize(deserializer)
            .map_err(|err| CatalogError::Invalid(format!("{}: {}", err.path(), err.inner())))?;
        catalog.validate()?;
        Ok(catalog)
    }

    /// Validates catalog consistency.
    ///
    /// # Errors
    ///
    /// Returns an error if the catalog contains invalid or inconsistent entries.
    pub fn validate(&self) -> Result<(), CatalogError> {
        validation::validate_catalog(self)
    }
}

/// Renders the catalog JSON schema.
///
/// # Errors
///
/// Returns an error if the schema cannot be serialized.
pub fn schema_json() -> serde_json::Result<String> {
    serde_json::to_string_pretty(&schemars::schema_for!(Catalog))
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct Tool {
    /// Stable tool key used in status output and managed install paths.
    #[garde(length(min = 1))]
    pub name: String,
    /// Executables that prove the tool is present and healthy.
    #[garde(length(min = 1), dive)]
    pub bins: Vec<Bin>,
    /// Empty means all operating systems.
    #[serde(default)]
    pub platforms: Vec<HostOs>,
    /// Extra host predicates beyond OS/architecture.
    #[serde(default)]
    pub requires: Vec<HostRequirement>,
    /// Overrides the phase inferred from the action type.
    #[serde(default)]
    pub phase: Option<Phase>,
    #[garde(dive)]
    pub action: Action,
}

impl Tool {
    /// Returns whether this catalog entry applies to `host`.
    #[inline]
    pub fn supports_host(&self, host: Host) -> bool {
        (self.platforms.is_empty() || self.platforms.contains(&host.os))
            && self.requires.iter().copied().all(meets_requirement)
    }

    /// Returns the phase that controls install ordering.
    #[inline]
    #[must_use]
    pub fn phase(&self) -> Phase {
        self.phase.unwrap_or(match self.action {
            Action::Required | Action::Toolchain(_) => Phase::Prerequisites,
            Action::Archive(_) | Action::File(_) => Phase::Archives,
            Action::Package(_) => Phase::Packages,
            Action::Build(_) | Action::SourceBuild(_) => Phase::Builds,
        })
    }

    /// Labels installed binaries by provenance for doctor output.
    #[inline]
    #[must_use]
    pub const fn source_label(&self, managed: bool) -> &'static str {
        match (matches!(self.action, Action::Required), managed) {
            (_, true) => "bootstrap-managed",
            (true, false) => "bootstrap-required",
            (false, false) => "external",
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct Bin {
    /// Executable name as it should appear on `PATH`.
    #[garde(length(min = 1))]
    pub name: String,
    /// Command used to verify that the executable starts successfully.
    #[garde(length(min = 1))]
    pub version_argv: Vec<String>,
}

/// Install phases run in declaration order; later phases may rely on binaries
/// from earlier phases, but not the reverse.
#[derive(
    Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize, JsonSchema,
)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    Prerequisites,
    Archives,
    Packages,
    Builds,
}

/// Installation strategy for a catalog entry.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Action {
    /// A pre-bootstrap binary that must already be available.
    Required,
    /// Download a release archive and link files from it.
    Archive(#[garde(dive)] ArchiveAction),
    /// Download a standalone file and link it from the managed install root.
    File(#[garde(dive)] FileAction),
    /// Invoke a package manager and then verify/link the managed binary.
    Package(#[garde(dive)] PackageAction),
    /// Run a build command against a source tree already in this repository.
    Build(#[garde(dive)] BuildAction),
    /// Download a source archive, build it, and link build outputs.
    SourceBuild(#[garde(dive)] SourceBuildAction),
    /// Manage components under a version manager such as rustup or uv.
    Toolchain(#[garde(dive)] Box<ToolchainAction>),
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct ArchiveAction {
    /// Default source for platforms that do not override it.
    pub source: Option<Source>,
    /// Host-specific archive format, source, and link layout.
    #[garde(length(min = 1), dive)]
    pub platforms: Vec<ArchivePlatform>,
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

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct ArchivePlatform {
    pub when: Predicate,
    /// Template value exposed as `{platform}` in source URLs and link paths.
    #[garde(length(min = 1))]
    pub platform: String,
    /// Per-platform source override.
    pub source: Option<Source>,
    pub kind: ArchiveKind,
    /// Leading archive path components to discard during extraction.
    pub strip_components: usize,
    /// Files to link into the managed binary directory.
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

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct Link {
    /// Link name to create in the destination directory.
    #[garde(length(min = 1))]
    pub name: String,
    /// Relative path under the install root.
    pub path: String,
    /// Environment variables to export from a generated wrapper before execing
    /// the linked binary.
    #[serde(default)]
    #[garde(dive)]
    pub env: Vec<EnvVar>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct EnvVar {
    #[garde(length(min = 1))]
    pub name: String,
    pub value: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct PackageAction {
    #[garde(length(min = 1))]
    pub name: String,
    /// Install command; `{package}` expands to `name`.
    #[garde(length(min = 1))]
    pub install_argv: Vec<String>,
    /// Optional package-manager inventory used to decide ownership.
    pub inventory: Option<Inventory>,
}

/// Package managers whose installed-file inventory can be queried.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Inventory {
    Uv,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct BuildAction {
    /// Repository-relative build directory.
    pub path: String,
    /// Build command; supports `{repo_dir}`, `{build_dir}`, `{prefix}`, and `{tool}`.
    #[garde(length(min = 1))]
    pub argv: Vec<String>,
    /// Explicit links from `{prefix}`; empty means `bin/<tool bin>`.
    #[serde(default)]
    #[garde(dive)]
    pub links: Vec<Link>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct SourceBuildAction {
    #[garde(length(min = 1))]
    pub version: String,
    #[garde(length(min = 1), dive)]
    pub platforms: Vec<SourceBuildPlatform>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct SourceBuildPlatform {
    pub when: Predicate,
    /// Template value exposed as `{platform}` in source URLs and link paths.
    #[garde(length(min = 1))]
    pub platform: String,
    #[garde(length(min = 1))]
    pub url: String,
    /// File name to use for the downloaded source archive.
    pub archive_file: String,
    pub kind: ArchiveKind,
    pub strip_components: usize,
    /// Optional build command run from the extracted source directory.
    ///
    /// If this is empty, the extracted source tree is installed directly.
    #[serde(default)]
    pub argv: Vec<String>,
    /// Whether to run the build command with an isolated fake home/cache.
    #[serde(default)]
    pub sandbox_home: bool,
    #[garde(length(min = 1), dive)]
    pub links: Vec<Link>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct DownloadCommand {
    pub when: Predicate,
    #[garde(length(min = 1))]
    pub url: String,
    /// Local file name for the downloaded executable.
    pub file: String,
    /// Command to run; supports `{file}`, `{toolchain}`, and `{components}`.
    #[garde(length(min = 1))]
    pub argv: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct ToolchainAction {
    /// Version-manager executable used to manage components.
    #[garde(length(min = 1))]
    pub manager_bin: String,
    /// Toolchain/channel name passed to the manager.
    #[garde(length(min = 1))]
    pub name: String,
    /// Optional environment variable that overrides `name`.
    pub name_env: Option<String>,
    #[garde(dive)]
    pub bin_dir: ToolchainBinDir,
    /// Components expected to be installed for this toolchain.
    #[garde(length(min = 1))]
    pub components: Vec<String>,
    #[garde(dive)]
    pub install: ToolchainInstall,
    /// Command that updates the manager or selected toolchain.
    #[garde(length(min = 1))]
    pub update_argv: Vec<String>,
    /// Command that checks whether `name` is currently active.
    #[garde(length(min = 1))]
    pub active_argv: Vec<String>,
    /// Command that makes `name` the default toolchain.
    #[garde(length(min = 1))]
    pub default_argv: Vec<String>,
    /// Command template used once per component.
    #[garde(length(min = 1))]
    pub component_argv: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct ToolchainBinDir {
    /// Environment variable that can point at the executable directory.
    pub env_var: Option<String>,
    /// Fallback path under the user's home directory.
    pub home_relative: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
pub struct ToolchainInstall {
    #[garde(length(min = 1), dive)]
    pub platforms: Vec<DownloadCommand>,
}
