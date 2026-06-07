use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

use crate::platform::Predicate;

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct DownloadCommand {
    pub when: Predicate,
    #[garde(length(min = 1))]
    pub url: String,
    /// Local file name for the downloaded executable.
    #[serde(default)]
    pub file: String,
    /// Command to run; supports `{{ file }}`, `{{ toolchain }}`, and `{{ components }}`.
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
