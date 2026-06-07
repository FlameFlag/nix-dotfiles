use schemars::JsonSchema;
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, JsonSchema, garde::Validate)]
#[garde(allow_unvalidated)]
pub struct PackageAction {
    #[serde(default)]
    #[garde(length(min = 1))]
    pub name: String,
    /// Install command; `{{ package }}` expands to `name`.
    #[serde(default)]
    #[garde(length(min = 1))]
    pub install_argv: Vec<String>,
    /// Optional package-manager inventory used to decide ownership.
    #[serde(default)]
    pub inventory: Option<Inventory>,
}

impl PackageAction {
    pub(super) fn apply_defaults(&mut self, tool_name: &str) {
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
    [
        "uv",
        "tool",
        "install",
        "--upgrade",
        "--force",
        "{{ package }}",
    ]
    .map(str::to_owned)
    .to_vec()
}

/// Package managers whose installed-file inventory can be queried.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum Inventory {
    Uv,
}
