#[cfg(unix)]
use std::io::Read;
#[cfg(unix)]
use std::path::Component;
use std::path::{Path, PathBuf};

use dotfiles_common::fs;
use fs_err as fse;
use thiserror::Error;

use crate::Context;
use crate::catalog::Link;

#[derive(Debug, Error)]
pub enum LinkError {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error("refusing to replace non-managed link {0}")]
    NonManagedLinkExists(PathBuf),
    #[error("environment wrapper links are not supported without shell shims: {0}")]
    EnvWrapperUnsupported(String),
}

#[must_use]
pub fn install_dir(ctx: &Context, tool: &str, version: &str) -> PathBuf {
    ctx.opt_dir.join(tool).join(version)
}

/// Creates managed links for all supplied link specs.
///
/// # Errors
///
/// Returns an error if any target cannot be made executable or linked safely.
pub fn link_many(
    ctx: &Context,
    tool: &str,
    install_dir: &Path,
    links: &[Link],
) -> Result<(), LinkError> {
    for link in links {
        let target = install_dir.join(&link.path);
        managed_link_default(ctx, tool, &target, link)?;
    }
    Ok(())
}

/// Creates managed links, adopting existing link paths if needed.
///
/// # Errors
///
/// Returns an error if any target cannot be made executable or linked safely.
pub fn link_many_adopt_existing(
    ctx: &Context,
    tool: &str,
    install_dir: &Path,
    links: &[Link],
) -> Result<(), LinkError> {
    for link in links {
        let target = install_dir.join(&link.path);
        managed_link(ctx, tool, &target, link, ExistingLinkPolicy::AdoptExisting)?;
    }
    Ok(())
}

fn managed_link(
    ctx: &Context,
    tool: &str,
    target: &Path,
    link: &Link,
    policy: ExistingLinkPolicy,
) -> Result<(), LinkError> {
    if !link.env.is_empty() {
        return Err(LinkError::EnvWrapperUnsupported(link.name.clone()));
    }
    managed_with_policy(ctx, tool, target, &link.name, policy)
}

fn managed_link_default(
    ctx: &Context,
    tool: &str,
    target: &Path,
    link: &Link,
) -> Result<(), LinkError> {
    managed_link(ctx, tool, target, link, ExistingLinkPolicy::ManagedOnly)
}

/// Creates or replaces a managed link for `target`.
///
/// # Errors
///
/// Returns an error if permissions cannot be updated or an existing non-managed link would be replaced.
pub fn managed(ctx: &Context, tool: &str, target: &Path, bin: &str) -> Result<(), LinkError> {
    managed_with_policy(ctx, tool, target, bin, ExistingLinkPolicy::ManagedOnly)
}

/// Creates or replaces a link, allowing an existing external link/file to be adopted.
///
/// # Errors
///
/// Returns an error if permissions cannot be updated or an existing directory blocks the link.
pub fn managed_adopt_existing(
    ctx: &Context,
    tool: &str,
    target: &Path,
    bin: &str,
) -> Result<(), LinkError> {
    managed_with_policy(ctx, tool, target, bin, ExistingLinkPolicy::AdoptExisting)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ExistingLinkPolicy {
    ManagedOnly,
    AdoptExisting,
}

fn managed_with_policy(
    ctx: &Context,
    tool: &str,
    target: &Path,
    bin: &str,
    policy: ExistingLinkPolicy,
) -> Result<(), LinkError> {
    #[cfg(windows)]
    let _ = (tool, policy);

    fs::make_executable(target)?;
    fse::create_dir_all(&ctx.bin_dir)?;
    let link_path = ctx.bin_dir.join(managed_link_name(target, bin));

    #[cfg(windows)]
    {
        // Windows cannot execute Unix-style symlinks reliably from every shell,
        // so managed links are materialized as copies or small batch wrappers.
        if is_windows_batch_file(&link_path) || is_windows_batch_file(target) {
            write_windows_batch_wrapper(target, &link_path)?;
        } else {
            fse::copy(target, &link_path)?;
        }
        return Ok(());
    }

    #[cfg(unix)]
    {
        use std::os::unix::fs as unix_fs;
        match fse::read_link(&link_path) {
            Ok(old_target) => {
                // Only replace links that already point into this tool's managed
                // opt directory. Anything else may belong to the user or another manager.
                let old_target = resolved_symlink_target(&link_path, old_target);
                if policy == ExistingLinkPolicy::ManagedOnly
                    && !fs::relative_under(ctx.opt_dir.join(tool), &old_target)
                {
                    return Err(LinkError::NonManagedLinkExists(link_path));
                }
                fse::remove_file(&link_path)?;
            }
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(_) => {
                let metadata = fse::symlink_metadata(&link_path)?;
                if metadata.is_dir() {
                    return Err(LinkError::NonManagedLinkExists(link_path));
                }
                if policy == ExistingLinkPolicy::ManagedOnly
                    && !is_previous_managed_copy(ctx, tool, target, &link_path)?
                {
                    return Err(LinkError::NonManagedLinkExists(link_path));
                }
                fse::remove_file(&link_path)?;
            }
        }
        unix_fs::symlink(target, link_path)?;
        Ok(())
    }
}

#[cfg(unix)]
fn resolved_symlink_target(link_path: &Path, target: PathBuf) -> PathBuf {
    if target.is_absolute() {
        target
    } else {
        link_path
            .parent()
            .map_or(target.clone(), |parent| parent.join(target))
    }
}

#[cfg(unix)]
fn is_previous_managed_copy(
    ctx: &Context,
    tool: &str,
    target: &Path,
    existing: &Path,
) -> Result<bool, LinkError> {
    let tool_root = ctx.opt_dir.join(tool);
    let Ok(target_relative) = target.strip_prefix(&tool_root) else {
        return Ok(false);
    };
    let Some(payload_relative) = path_after_first_component(target_relative) else {
        return Ok(false);
    };
    let metadata = fse::metadata(existing)?;
    if !metadata.is_file() {
        return Ok(false);
    }

    for entry in fse::read_dir(&tool_root)? {
        let entry = entry?;
        let candidate = entry.path().join(&payload_relative);
        if candidate == target || !candidate.is_file() {
            continue;
        }
        if files_equal(existing, &candidate)? {
            return Ok(true);
        }
    }

    Ok(false)
}

#[cfg(unix)]
fn path_after_first_component(path: &Path) -> Option<PathBuf> {
    let mut components = path.components();
    match components.next()? {
        Component::Normal(_) => {}
        _ => return None,
    }
    let rest = components.as_path();
    (!rest.as_os_str().is_empty()).then(|| rest.to_path_buf())
}

#[cfg(unix)]
fn files_equal(left: &Path, right: &Path) -> Result<bool, LinkError> {
    let left_metadata = fse::metadata(left)?;
    let right_metadata = fse::metadata(right)?;
    if left_metadata.len() != right_metadata.len() {
        return Ok(false);
    }

    let mut left = fse::File::open(left)?;
    let mut right = fse::File::open(right)?;
    let mut left_buf = [0; 8192];
    let mut right_buf = [0; 8192];
    loop {
        let left_read = left.read(&mut left_buf)?;
        let right_read = right.read(&mut right_buf)?;
        if left_read != right_read {
            return Ok(false);
        }
        if left_read == 0 {
            return Ok(true);
        }
        if left_buf[..left_read] != right_buf[..right_read] {
            return Ok(false);
        }
    }
}

fn managed_link_name(target: &Path, bin: &str) -> String {
    let target_extension = target.extension();
    if cfg!(windows)
        && Path::new(bin).extension().is_none()
        && target_extension.is_some_and(|ext| {
            matches!(
                ext.to_string_lossy().to_ascii_lowercase().as_str(),
                "exe" | "cmd" | "bat" | "com"
            )
        })
    {
        let extension = target_extension
            .map(|ext| ext.to_string_lossy())
            .unwrap_or_default();
        format!("{bin}.{extension}")
    } else {
        bin.to_owned()
    }
}

#[cfg(windows)]
fn is_windows_batch_file(path: &Path) -> bool {
    path.extension().is_some_and(|ext| {
        matches!(
            ext.to_string_lossy().to_ascii_lowercase().as_str(),
            "bat" | "cmd"
        )
    })
}

#[cfg(windows)]
fn write_windows_batch_wrapper(target: &Path, link_path: &Path) -> Result<(), LinkError> {
    let target = target.to_string_lossy().replace('%', "%%");
    fse::write(link_path, format!("@echo off\r\n\"{target}\" %*\r\n"))?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn context() -> (tempfile::TempDir, Context) {
        let temp = tempfile::tempdir().expect("tempdir");
        let ctx = Context::new_with_home(temp.path().join("repo"), Some(temp.path().join("home")))
            .expect("context");
        (temp, ctx)
    }

    fn write_target(ctx: &Context, tool: &str, version: &str, name: &str) -> PathBuf {
        let target = ctx.opt_dir.join(tool).join(version).join("bin").join(name);
        fse::create_dir_all(target.parent().expect("parent")).expect("create parent");
        fse::write(&target, "#!/bin/sh\n").expect("write target");
        target
    }

    #[test]
    fn managed_link_creates_bin_link() {
        let (_temp, ctx) = context();
        let target = write_target(&ctx, "demo", "1", "demo");

        managed(&ctx, "demo", &target, "demo").expect("create managed link");

        assert!(ctx.bin_dir.join("demo").exists());
    }

    #[cfg(unix)]
    #[test]
    fn managed_link_replaces_only_managed_links() {
        let (_temp, ctx) = context();
        let first = write_target(&ctx, "demo", "1", "demo");
        let second = write_target(&ctx, "demo", "2", "demo");
        managed(&ctx, "demo", &first, "demo").expect("create first link");

        managed(&ctx, "demo", &second, "demo").expect("replace managed link");

        assert_eq!(
            fse::read_link(ctx.bin_dir.join("demo")).expect("read link"),
            second
        );
    }

    #[cfg(unix)]
    #[test]
    fn managed_link_rejects_external_links_unless_adopted() {
        let (temp, ctx) = context();
        let target = write_target(&ctx, "demo", "1", "demo");
        let external = temp.path().join("external");
        fse::write(&external, "").expect("write external");
        std::os::unix::fs::symlink(&external, ctx.bin_dir.join("demo")).expect("external symlink");

        assert!(matches!(
            managed(&ctx, "demo", &target, "demo"),
            Err(LinkError::NonManagedLinkExists(_))
        ));

        managed_adopt_existing(&ctx, "demo", &target, "demo").expect("adopt link");
        assert_eq!(
            fse::read_link(ctx.bin_dir.join("demo")).expect("read link"),
            target
        );
    }

    #[cfg(unix)]
    #[test]
    fn managed_adopt_existing_replaces_existing_files() {
        let (_temp, ctx) = context();
        let target = write_target(&ctx, "demo", "1", "demo");
        fse::write(ctx.bin_dir.join("demo"), "old direct install").expect("write existing file");

        managed_adopt_existing(&ctx, "demo", &target, "demo").expect("adopt file");

        assert_eq!(
            fse::read_link(ctx.bin_dir.join("demo")).expect("read link"),
            target
        );
    }

    #[cfg(unix)]
    #[test]
    fn managed_link_replaces_previous_managed_file_copy() {
        let (_temp, ctx) = context();
        let previous = write_target(&ctx, "demo", "1", "demo");
        let current = write_target(&ctx, "demo", "2", "demo");
        fse::copy(&previous, ctx.bin_dir.join("demo")).expect("copy previous binary");

        managed(&ctx, "demo", &current, "demo").expect("replace previous copy");

        assert_eq!(
            fse::read_link(ctx.bin_dir.join("demo")).expect("read link"),
            current
        );
    }

    #[cfg(unix)]
    #[test]
    fn managed_link_rejects_unrelated_existing_files() {
        let (_temp, ctx) = context();
        let target = write_target(&ctx, "demo", "1", "demo");
        fse::write(ctx.bin_dir.join("demo"), "external direct install")
            .expect("write existing file");

        assert!(matches!(
            managed(&ctx, "demo", &target, "demo"),
            Err(LinkError::NonManagedLinkExists(_))
        ));
    }

    #[cfg(unix)]
    #[test]
    fn managed_adopt_existing_rejects_existing_directories() {
        let (_temp, ctx) = context();
        let target = write_target(&ctx, "demo", "1", "demo");
        fse::create_dir(ctx.bin_dir.join("demo")).expect("create blocking directory");

        assert!(matches!(
            managed_adopt_existing(&ctx, "demo", &target, "demo"),
            Err(LinkError::NonManagedLinkExists(_))
        ));
    }
}
