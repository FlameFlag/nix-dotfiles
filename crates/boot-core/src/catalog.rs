use std::path::Path;

use fs_err as fs;
use schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use thiserror::Error;

use crate::platform::{Host, HostOs, HostRequirement, meets_requirement};

mod archive;
mod bin;
mod build;
mod link;
mod package;
mod source;
#[cfg(test)]
mod tests;
mod toolchain;
mod validation;

pub use archive::{ArchiveAction, ArchiveKind, ArchivePlatform, FileAction};
pub use bin::Bin;
pub use build::{BuildAction, SourceBuildAction, SourceBuildPlatform};
pub use link::{EnvVar, Link};
pub use package::{Inventory, PackageAction};
pub use source::Source;
pub use toolchain::{DownloadCommand, ToolchainAction, ToolchainBinDir, ToolchainInstall};

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

/// Install phases run in declaration order; later phases may rely on binaries
/// from earlier phases, but not the reverse.
#[derive(
    Debug,
    Clone,
    Copy,
    PartialEq,
    Eq,
    PartialOrd,
    Ord,
    Serialize,
    Deserialize,
    JsonSchema,
    strum::Display,
)]
#[serde(rename_all = "snake_case")]
#[strum(serialize_all = "snake_case")]
pub enum Phase {
    Prerequisites,
    Archives,
    Packages,
    Builds,
}

/// Installation strategy for a catalog entry.
#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate, strum::Display)]
#[serde(tag = "type", rename_all = "snake_case")]
#[strum(serialize_all = "kebab-case")]
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
