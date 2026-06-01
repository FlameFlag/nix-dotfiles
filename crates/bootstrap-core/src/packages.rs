use std::collections::HashMap;

use dotfiles_common::process;

use crate::Context;
use crate::catalog::{Action, Catalog, Inventory, PackageAction};
use crate::platform::Host;

#[derive(Debug, Default)]
pub struct PackageInventory {
    uv: HashMap<String, String>,
}

impl PackageInventory {
    /// Collects package inventory from supported package managers.
    ///
    /// # Errors
    ///
    /// Returns an error if an invoked package manager command fails to run.
    pub fn collect(ctx: &Context) -> Result<Self, process::ProcessError> {
        let Some(uv_path) =
            process::path_in_dir(&ctx.bin_dir, "uv").or_else(|| process::path_of("uv"))
        else {
            return Ok(Self::default());
        };
        let argv = vec![
            uv_path.to_string_lossy().into_owned(),
            "tool".into(),
            "list".into(),
            "--show-paths".into(),
        ];
        let text = process::trimmed_text_with_env(&argv, ctx.command_env())?;
        Ok(Self {
            uv: parse_uv_tool_list(&text),
        })
    }

    pub fn collect_for_catalog(
        ctx: &Context,
        catalog: &Catalog,
    ) -> Result<Self, process::ProcessError> {
        let host = Host::current();
        if catalog.tools.iter().any(|tool| {
            tool.supports_host(host)
                && matches!(
                    &tool.action,
                    Action::Package(package) if package.inventory.is_some()
                )
        }) {
            Self::collect(ctx)
        } else {
            Ok(Self::default())
        }
    }

    pub fn collect_for_package(
        ctx: &Context,
        package: &PackageAction,
    ) -> Result<Self, process::ProcessError> {
        if package.inventory.is_some() {
            Self::collect(ctx)
        } else {
            Ok(Self::default())
        }
    }

    #[must_use]
    pub fn bin_is_managed(&self, package: &PackageAction, bin: &str, path: &str) -> bool {
        match package.inventory {
            Some(Inventory::Uv) => self.uv.get(bin).is_some_and(|listed| listed == path),
            None => false,
        }
    }
}

fn parse_uv_tool_list(text: &str) -> HashMap<String, String> {
    let mut bins = HashMap::new();
    for line in text.lines() {
        let trimmed = line.trim();
        if !trimmed.starts_with("- ") || !trimmed.ends_with(')') {
            continue;
        }
        let Some(open) = trimmed.rfind('(') else {
            continue;
        };
        let bin = trimmed[2..open].trim();
        let path = &trimmed[open + 1..trimmed.len() - 1];
        bins.insert(bin.to_owned(), path.to_owned());
    }
    bins
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::{Bin, Tool};

    #[test]
    fn parses_uv_bins() {
        let bins = parse_uv_tool_list(
            "ruff v0.1.0 (/tools/ruff)\n- ruff (/home/me/.local/bin/ruff)\n- ruff-lsp (/home/me/.local/bin/ruff-lsp)",
        );
        assert_eq!(bins["ruff"], "/home/me/.local/bin/ruff");
        assert_eq!(bins["ruff-lsp"], "/home/me/.local/bin/ruff-lsp");
    }

    #[test]
    fn skips_inventory_collection_when_catalog_has_no_inventory_backed_packages() {
        let temp = tempfile::tempdir().expect("tempdir");
        let ctx = Context::new_with_home(temp.path().join("repo"), Some(temp.path().join("home")))
            .expect("context");
        let catalog = Catalog {
            tools: vec![Tool {
                name: "sh".into(),
                bins: vec![Bin {
                    name: "sh".into(),
                    version_argv: vec!["sh".into(), "--version".into()],
                }],
                platforms: vec![],
                requires: vec![],
                phase: None,
                action: Action::Required,
            }],
        };

        PackageInventory::collect_for_catalog(&ctx, &catalog).expect("inventory");
    }
}
