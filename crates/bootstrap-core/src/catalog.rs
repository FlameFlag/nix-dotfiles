use std::path::Path;

use fs_err as fs;
use schemars::{JsonSchema, Schema, SchemaGenerator, json_schema};
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
        let mut catalog: Self = serde_path_to_error::deserialize(deserializer)
            .map_err(|err| CatalogError::Invalid(format!("{}: {}", err.path(), err.inner())))?;
        catalog.apply_defaults();
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

    fn apply_defaults(&mut self) {
        for tool in &mut self.tools {
            if tool.bins.is_empty() {
                tool.bins.push(Bin::for_name(&tool.name));
            }
            match &mut tool.action {
                Action::Package(action) => action.apply_defaults(&tool.name),
                Action::Build(action) => action.apply_defaults(),
                _ => {}
            }
        }
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
    #[serde(default)]
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

#[derive(Debug, Clone, Serialize, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct Bin {
    /// Executable name as it should appear on `PATH`.
    #[garde(length(min = 1))]
    pub name: String,
    /// Command used to verify that the executable starts successfully.
    #[garde(length(min = 1))]
    pub version_argv: Vec<String>,
}

impl JsonSchema for Bin {
    fn inline_schema() -> bool {
        true
    }

    fn schema_name() -> std::borrow::Cow<'static, str> {
        "Bin".into()
    }

    fn json_schema(_generator: &mut SchemaGenerator) -> Schema {
        json_schema!({
            "oneOf": [
                { "type": "string" },
                {
                    "type": "object",
                    "required": ["name"],
                    "properties": {
                        "name": { "type": "string" },
                        "version_argv": {
                            "type": "array",
                            "items": { "type": "string" }
                        }
                    },
                    "additionalProperties": false
                }
            ]
        })
    }
}

impl Bin {
    fn for_name(name: &str) -> Self {
        Self {
            name: name.to_owned(),
            version_argv: default_version_argv(name),
        }
    }
}

impl<'de> Deserialize<'de> for Bin {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum BinRepr {
            Name(String),
            Full {
                name: String,
                #[serde(default)]
                version_argv: Vec<String>,
            },
        }

        match BinRepr::deserialize(deserializer)? {
            BinRepr::Name(name) => Ok(Bin::for_name(&name)),
            BinRepr::Full { name, version_argv } => Ok(Bin {
                version_argv: if version_argv.is_empty() {
                    default_version_argv(&name)
                } else {
                    version_argv
                },
                name,
            }),
        }
    }
}

fn default_version_argv(name: &str) -> Vec<String> {
    vec![name.to_owned(), "--version".to_owned()]
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

#[derive(Debug, Clone, Serialize, garde::Validate)]
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

impl JsonSchema for Link {
    fn inline_schema() -> bool {
        true
    }

    fn schema_name() -> std::borrow::Cow<'static, str> {
        "Link".into()
    }

    fn json_schema(_generator: &mut SchemaGenerator) -> Schema {
        json_schema!({
            "oneOf": [
                { "type": "string" },
                {
                    "type": "object",
                    "required": ["name"],
                    "properties": {
                        "name": { "type": "string" },
                        "path": { "type": "string" },
                        "env": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "required": ["name", "value"],
                                "properties": {
                                    "name": { "type": "string" },
                                    "value": { "type": "string" }
                                },
                                "additionalProperties": false
                            }
                        }
                    },
                    "additionalProperties": false
                }
            ]
        })
    }
}

impl<'de> Deserialize<'de> for Link {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        #[derive(Deserialize)]
        #[serde(untagged)]
        enum LinkRepr {
            Name(String),
            Full {
                name: String,
                path: Option<String>,
                #[serde(default)]
                env: Vec<EnvVar>,
            },
        }

        match LinkRepr::deserialize(deserializer)? {
            LinkRepr::Name(name) => Ok(Self {
                path: name.clone(),
                name,
                env: Vec::new(),
            }),
            LinkRepr::Full { name, path, env } => Ok(Self {
                path: path.unwrap_or_else(|| name.clone()),
                name,
                env,
            }),
        }
    }
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
    #[serde(default)]
    #[garde(length(min = 1))]
    pub name: String,
    /// Install command; `{package}` expands to `name`.
    #[serde(default)]
    #[garde(length(min = 1))]
    pub install_argv: Vec<String>,
    /// Optional package-manager inventory used to decide ownership.
    #[serde(default)]
    pub inventory: Option<Inventory>,
}

impl PackageAction {
    fn apply_defaults(&mut self, tool_name: &str) {
        if self.name.is_empty() {
            self.name = tool_name.to_owned();
        }
        if self.install_argv.is_empty() {
            self.install_argv = default_uv_tool_install_argv();
        }
        if self.inventory.is_none() && self.install_argv == default_uv_tool_install_argv() {
            self.inventory = Some(Inventory::Uv);
        }
    }
}

fn default_uv_tool_install_argv() -> Vec<String> {
    ["uv", "tool", "install", "--upgrade", "--force", "{package}"]
        .map(str::to_owned)
        .to_vec()
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
    #[serde(default)]
    #[garde(length(min = 1))]
    pub argv: Vec<String>,
    /// Explicit links from `{prefix}`; empty means `bin/<tool bin>`.
    #[serde(default)]
    #[garde(dive)]
    pub links: Vec<Link>,
}

impl BuildAction {
    fn apply_defaults(&mut self) {
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
        "{build_dir}",
        "--root",
        "{prefix}",
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
    /// Template value exposed as `{platform}` in source URLs and link paths.
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

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct DownloadCommand {
    pub when: Predicate,
    #[garde(length(min = 1))]
    pub url: String,
    /// Local file name for the downloaded executable.
    #[serde(default)]
    pub file: String,
    /// Command to run; supports `{file}`, `{toolchain}`, and `{components}`.
    #[serde(default)]
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
#[garde(allow_unvalidated)]
pub struct ToolchainInstall {
    /// Default local installer file name for platforms that do not override it.
    #[serde(default)]
    pub file: String,
    /// Default installer command for platforms that do not override it.
    #[serde(default)]
    pub argv: Vec<String>,
    #[garde(length(min = 1), dive)]
    pub platforms: Vec<DownloadCommand>,
}

impl ToolchainInstall {
    #[must_use]
    pub fn platform_file<'a>(&'a self, command: &'a DownloadCommand) -> Option<&'a str> {
        if command.file.is_empty() {
            non_empty(&self.file)
        } else {
            Some(&command.file)
        }
    }

    #[must_use]
    pub fn platform_argv<'a>(&'a self, command: &'a DownloadCommand) -> Option<&'a [String]> {
        if command.argv.is_empty() {
            non_empty_slice(&self.argv)
        } else {
            Some(&command.argv)
        }
    }
}

fn non_empty(value: &str) -> Option<&str> {
    (!value.is_empty()).then_some(value)
}

fn non_empty_slice<T>(value: &[T]) -> Option<&[T]> {
    (!value.is_empty()).then_some(value)
}
