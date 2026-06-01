use std::path::{Path, PathBuf};

use dotfiles_common::{fs, process};

use crate::catalog::{Action, Tool};
use crate::packages::PackageInventory;
use crate::{Context, toolchain};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Classification {
    Missing,
    /// Present and attributable to this bootstrap context.
    Managed,
    /// Present, but owned by the user, system, or another package manager.
    External,
}

/// Classifies a resolved executable path for install/doctor decisions.
#[must_use]
pub fn classify_bin(
    ctx: &Context,
    tool: &Tool,
    bin: &str,
    path: Option<&Path>,
    package_inventory: &PackageInventory,
) -> Classification {
    let Some(path) = path else {
        return Classification::Missing;
    };

    if let Action::Toolchain(spec) = &tool.action {
        let bin_dir = toolchain::bin_dir(ctx, spec);
        return if fs::relative_under(bin_dir, path) {
            Classification::Managed
        } else {
            Classification::External
        };
    }

    if !fs::relative_under(&ctx.bin_dir, path) {
        return Classification::External;
    }

    match &tool.action {
        Action::Build(_) | Action::File(_) => Classification::Managed,
        Action::Package(package) => {
            // Package-manager installs can land in the same bin directory as
            // bootstrap-managed shims, so confirm ownership with inventory data.
            if package_inventory.bin_is_managed(package, bin, &path.to_string_lossy()) {
                Classification::Managed
            } else {
                Classification::External
            }
        }
        Action::Archive(_) | Action::SourceBuild(_) | Action::Required => {
            if cfg!(windows) {
                // Windows links are copied/wrapped into bin_dir, leaving no
                // symlink target to inspect.
                Classification::Managed
            } else {
                symlink_target(path)
                    .filter(|target| fs::relative_under(ctx.opt_dir.join(&tool.name), target))
                    .map_or(Classification::External, |_| Classification::Managed)
            }
        }
        Action::Toolchain(_) => Classification::External,
    }
}

#[must_use]
pub fn classify_bin_on_path(
    ctx: &Context,
    tool: &Tool,
    bin: &str,
    package_inventory: &PackageInventory,
) -> Classification {
    let path = process::path_of(bin);
    classify_bin(ctx, tool, bin, path.as_deref(), package_inventory)
}

fn symlink_target(path: &Path) -> Option<PathBuf> {
    let raw = fs_err::read_link(path).ok()?;
    if raw.is_absolute() {
        Some(raw)
    } else {
        path.parent().map(|parent| parent.join(raw))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::catalog::{Bin, BuildAction, ToolchainAction, ToolchainBinDir, ToolchainInstall};

    fn context() -> (tempfile::TempDir, Context) {
        let temp = tempfile::tempdir().expect("tempdir");
        let ctx = Context::new_with_home(temp.path().join("repo"), Some(temp.path().join("home")))
            .expect("context");
        (temp, ctx)
    }

    fn tool(action: Action) -> Tool {
        Tool {
            name: "demo".into(),
            bins: vec![Bin {
                name: "demo".into(),
                version_argv: vec!["demo".into(), "--version".into()],
            }],
            platforms: vec![],
            requires: vec![],
            phase: None,
            action,
        }
    }

    fn toolchain_action() -> ToolchainAction {
        ToolchainAction {
            manager_bin: "demo".into(),
            name: "stable".into(),
            name_env: None,
            bin_dir: ToolchainBinDir {
                env_var: None,
                home_relative: ".toolchain/bin".into(),
            },
            components: vec!["demo".into()],
            install: ToolchainInstall { platforms: vec![] },
            update_argv: vec!["demo".into(), "update".into()],
            active_argv: vec!["demo".into(), "active".into()],
            default_argv: vec!["demo".into(), "default".into()],
            component_argv: vec!["--component".into(), "{component}".into()],
        }
    }

    #[test]
    fn classifies_missing_and_external_bins() {
        let (temp, ctx) = context();
        let tool = tool(Action::Build(BuildAction {
            path: "demo".into(),
            argv: vec!["cargo".into(), "build".into()],
            links: vec![],
        }));
        let external = temp.path().join("external-demo");
        fs_err::write(&external, "").expect("write external file");

        assert_eq!(
            classify_bin(&ctx, &tool, "demo", None, &PackageInventory::default()),
            Classification::Missing
        );
        assert_eq!(
            classify_bin(
                &ctx,
                &tool,
                "demo",
                Some(&external),
                &PackageInventory::default()
            ),
            Classification::External
        );
    }

    #[test]
    fn classifies_build_bins_under_managed_bin_dir() {
        let (_temp, ctx) = context();
        let tool = tool(Action::Build(BuildAction {
            path: "demo".into(),
            argv: vec!["cargo".into(), "build".into()],
            links: vec![],
        }));
        let managed = ctx.bin_dir.join("demo");
        fs_err::write(&managed, "").expect("write managed file");

        assert_eq!(
            classify_bin(
                &ctx,
                &tool,
                "demo",
                Some(&managed),
                &PackageInventory::default()
            ),
            Classification::Managed
        );
    }

    #[test]
    fn classifies_toolchain_bins_by_toolchain_bin_dir() {
        let (_temp, ctx) = context();
        let action = toolchain_action();
        let managed = toolchain::bin_dir(&ctx, &action).join("demo");
        fs_err::create_dir_all(managed.parent().expect("parent")).expect("create parent");
        fs_err::write(&managed, "").expect("write managed file");
        let tool = tool(Action::Toolchain(Box::new(action)));

        assert_eq!(
            classify_bin(
                &ctx,
                &tool,
                "demo",
                Some(&managed),
                &PackageInventory::default()
            ),
            Classification::Managed
        );
    }

    #[cfg(unix)]
    #[test]
    fn classifies_archive_bins_by_symlink_target() {
        use crate::catalog::{ArchiveAction, ArchiveKind, ArchivePlatform, Link};

        let (_temp, ctx) = context();
        let install_bin = ctx
            .opt_dir
            .join("demo")
            .join("latest")
            .join("bin")
            .join("demo");
        fs_err::create_dir_all(install_bin.parent().expect("parent")).expect("create parent");
        fs_err::write(&install_bin, "").expect("write install file");
        let linked_bin = ctx.bin_dir.join("demo");
        std::os::unix::fs::symlink(&install_bin, &linked_bin).expect("symlink");
        let tool = tool(Action::Archive(ArchiveAction {
            source: None,
            platforms: vec![ArchivePlatform {
                when: Default::default(),
                platform: "test".into(),
                source: None,
                kind: ArchiveKind::TarGz,
                strip_components: 0,
                links: vec![Link {
                    name: "demo".into(),
                    path: "bin/demo".into(),
                    env: vec![],
                }],
                app_links: vec![],
            }],
        }));

        assert_eq!(
            classify_bin(
                &ctx,
                &tool,
                "demo",
                Some(&linked_bin),
                &PackageInventory::default()
            ),
            Classification::Managed
        );
    }
}
