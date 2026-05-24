use std::path::Path;

use dotfiles_common::fs;
use thiserror::Error;
use toml_edit::{Array, DocumentMut, Item, Table, value};

use crate::{Context, install, links, runtime};

#[derive(Debug, Error)]
pub enum SetupError {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Link(#[from] links::LinkError),
    #[error(transparent)]
    Install(#[from] install::InstallError),
    #[error(transparent)]
    Toml(#[from] toml_edit::TomlError),
}

/// Runs first-boot setup from a standalone `bootstrap` binary, then installs the catalog.
///
/// # Errors
///
/// Returns an error if setup files, self-installation, or catalog installation fails.
pub fn bootstrap(ctx: &Context) -> Result<(), SetupError> {
    prepare_bootstrap(ctx)?;
    install_catalog(ctx)
}

fn prepare_bootstrap(ctx: &Context) -> Result<(), SetupError> {
    ensure_shell_path(ctx)?;
    ensure_chezmoi_config(ctx)?;
    install_current_exe_if_needed(ctx)
}

fn install_current_exe_if_needed(ctx: &Context) -> Result<(), SetupError> {
    if runtime::skip_self_install() {
        Ok(())
    } else {
        install_current_exe(ctx)
    }
}

fn install_catalog(ctx: &Context) -> Result<(), SetupError> {
    Ok(install::install_all(ctx, install::Policy::InstallMissing)?)
}

/// Copies the running `bootstrap` executable into the managed bootstrap prefix.
///
/// # Errors
///
/// Returns an error if the executable cannot be copied or linked.
pub fn install_current_exe(ctx: &Context) -> Result<(), SetupError> {
    let source = std::env::current_exe()?;
    let bin_name = dotfiles_common::process::executable_name("bootstrap");
    let target = ctx
        .opt_dir
        .join("bootstrap")
        .join("bootstrap")
        .join("bin")
        .join(&bin_name);

    if !same_file(&source, &target) {
        if let Some(parent) = target.parent() {
            fs_err::create_dir_all(parent)?;
        }
        fs_err::copy(&source, &target)?;
        fs::make_executable(&target)?;
    }

    #[cfg(windows)]
    {
        let link_path = ctx.bin_dir.join(&bin_name);
        if same_file(&source, &link_path) {
            return Ok(());
        }
    }

    links::managed_adopt_existing(ctx, "bootstrap", &target, "bootstrap")?;
    remove_legacy_dev_tools_link(ctx)?;
    Ok(())
}

fn remove_legacy_dev_tools_link(ctx: &Context) -> Result<(), SetupError> {
    let legacy_path = ctx
        .bin_dir
        .join(dotfiles_common::process::executable_name("dev_tools"));
    let Ok(target) = fs_err::read_link(&legacy_path) else {
        return Ok(());
    };
    let target = if target.is_absolute() {
        target
    } else {
        legacy_path
            .parent()
            .map_or_else(|| target.clone(), |parent| parent.join(&target))
    };

    if dotfiles_common::fs::relative_under(ctx.opt_dir.join("dev_tools"), &target)
        || dotfiles_common::fs::relative_under(ctx.opt_dir.join("nix-dotfiles-bootstrap"), &target)
    {
        fs_err::remove_file(legacy_path)?;
    }
    Ok(())
}

fn ensure_shell_path(ctx: &Context) -> Result<(), SetupError> {
    #[cfg(windows)]
    {
        return ensure_windows_user_path(ctx);
    }

    #[cfg(not(windows))]
    ensure_unix_shell_path(ctx)
}

#[cfg(not(windows))]
fn ensure_unix_shell_path(ctx: &Context) -> Result<(), SetupError> {
    let path = ctx.home.join(".zshenv");
    let marker = "nix-dotfiles bootstrap PATH";
    let existing = fs_err::read_to_string(&path).unwrap_or_default();
    if existing.contains(marker) {
        return Ok(());
    }

    let mut addition = String::new();
    if !existing.is_empty() && !existing.ends_with('\n') {
        addition.push('\n');
    }
    if !existing.is_empty() {
        addition.push('\n');
    }
    addition.push_str("# ");
    addition.push_str(marker);
    addition.push('\n');
    addition.push_str("typeset -U path PATH 2>/dev/null || true\n");
    addition.push_str(
        "case \":${PATH}:\" in *\":${HOME}/.local/bin:\"*) ;; *) PATH=\"${HOME}/.local/bin:${PATH}\" ;; esac\n",
    );
    addition.push_str("export PATH\n");

    if let Some(parent) = path.parent() {
        fs_err::create_dir_all(parent)?;
    }
    use std::io::Write;
    let mut file = fs_err::OpenOptions::new()
        .create(true)
        .append(true)
        .open(path)?;
    file.write_all(addition.as_bytes())?;
    Ok(())
}

#[cfg(windows)]
fn ensure_windows_user_path(ctx: &Context) -> Result<(), SetupError> {
    use winreg::enums::{HKEY_CURRENT_USER, REG_EXPAND_SZ, REG_SZ};
    use winreg::types::FromRegValue;
    use winreg::{RegKey, RegValue};

    let hkcu = RegKey::predef(HKEY_CURRENT_USER);
    let (environment, _) = hkcu.create_subkey("Environment")?;
    let current = environment.get_raw_value("Path").ok();
    let current_text = current
        .as_ref()
        .and_then(|value| String::from_reg_value(value).ok())
        .unwrap_or_default();
    let bin_dir = ctx.bin_dir.to_string_lossy();
    let Some(updated) = append_path_entry(&current_text, &bin_dir, ';', true) else {
        return Ok(());
    };

    let value_type = current
        .as_ref()
        .map(|value| value.vtype.clone())
        .filter(|value_type| matches!(value_type, REG_SZ | REG_EXPAND_SZ))
        .unwrap_or(REG_EXPAND_SZ);
    environment.set_raw_value(
        "Path",
        &RegValue {
            bytes: encode_windows_registry_string(&updated),
            vtype: value_type,
        },
    )?;
    Ok(())
}

#[cfg(windows)]
fn encode_windows_registry_string(value: &str) -> Vec<u8> {
    value
        .encode_utf16()
        .chain(std::iter::once(0))
        .flat_map(u16::to_le_bytes)
        .collect()
}

#[cfg(any(windows, test))]
fn append_path_entry(
    current: &str,
    entry: &str,
    separator: char,
    case_insensitive: bool,
) -> Option<String> {
    let entry = entry.trim();
    if entry.is_empty()
        || current
            .split(separator)
            .any(|existing| path_entries_match(existing, entry, case_insensitive))
    {
        return None;
    }

    let current = current.trim_end_matches(separator);
    if current.is_empty() {
        Some(entry.to_owned())
    } else {
        Some(format!("{current}{separator}{entry}"))
    }
}

#[cfg(any(windows, test))]
fn path_entries_match(left: &str, right: &str, case_insensitive: bool) -> bool {
    let left = normalized_path_entry(left);
    let right = normalized_path_entry(right);
    if case_insensitive {
        left.eq_ignore_ascii_case(&right)
    } else {
        left == right
    }
}

#[cfg(any(windows, test))]
fn normalized_path_entry(entry: &str) -> String {
    let entry = entry.trim().trim_matches('"').replace('/', "\\");
    entry.trim_end_matches(['\\', '/']).to_owned()
}

fn ensure_chezmoi_config(ctx: &Context) -> Result<(), SetupError> {
    let config_home = if ctx.isolated_home {
        ctx.home.join(".config")
    } else {
        std::env::var_os("XDG_CONFIG_HOME")
            .map(std::path::PathBuf::from)
            .unwrap_or_else(|| ctx.home.join(".config"))
    };
    let config_dir = config_home.join("chezmoi");
    let config_file = config_dir.join("chezmoi.toml");
    let source_dir = ctx.repo_dir.join("dotfiles");
    fs_err::create_dir_all(&config_dir)?;

    let existing = fs_err::read_to_string(&config_file).unwrap_or_default();
    let mut doc = if existing.trim().is_empty() {
        DocumentMut::new()
    } else {
        existing.parse::<DocumentMut>()?
    };
    let mut changed = false;

    if !doc.as_table().contains_key("sourceDir") {
        doc["sourceDir"] = value(source_dir.to_string_lossy().as_ref());
        changed = true;
    }

    if !doc.as_table().contains_key("secret") || doc["secret"].as_table().is_none() {
        let mut secret = Table::new();
        let mut args = Array::default();
        args.push("--decrypt");
        secret["command"] = value("sops");
        secret["args"] = value(args);
        doc["secret"] = Item::Table(secret);
        changed = true;
    }

    if changed {
        fs_err::write(config_file, doc.to_string())?;
    }
    Ok(())
}

fn same_file(left: &Path, right: &Path) -> bool {
    let Ok(left) = fs_err::canonicalize(left) else {
        return false;
    };
    let Ok(right) = fs_err::canonicalize(right) else {
        return false;
    };
    left == right
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

    #[cfg(not(windows))]
    #[test]
    fn ensure_shell_path_adds_marker_once() {
        let (_temp, ctx) = context();
        ensure_shell_path(&ctx).expect("write shell path");
        ensure_shell_path(&ctx).expect("second shell path write");

        let text = fs_err::read_to_string(ctx.home.join(".zshenv")).expect("read zshenv");
        assert_eq!(text.matches("nix-dotfiles bootstrap PATH").count(), 1);
        assert!(text.contains("${HOME}/.local/bin"));
    }

    #[test]
    fn ensure_chezmoi_config_adds_source_and_secret_config() {
        let (_temp, ctx) = context();
        ensure_chezmoi_config(&ctx).expect("write chezmoi config");
        ensure_chezmoi_config(&ctx).expect("second chezmoi config write");

        let config = fs_err::read_to_string(
            ctx.home
                .join(".config")
                .join("chezmoi")
                .join("chezmoi.toml"),
        )
        .expect("read chezmoi config");
        assert!(config.contains("sourceDir"));
        assert!(config.contains("sops"));
    }

    #[test]
    fn same_file_compares_canonical_paths() {
        let temp = tempfile::tempdir().expect("tempdir");
        let file = temp.path().join("file");
        fs_err::write(&file, "").expect("write file");

        assert!(same_file(&file, &file));
        assert!(!same_file(&file, &temp.path().join("missing")));
    }

    #[test]
    fn append_path_entry_adds_missing_entry() {
        assert_eq!(
            append_path_entry(
                r"C:\Windows;C:\Tools",
                r"C:\Users\flame\.local\bin",
                ';',
                true
            ),
            Some(r"C:\Windows;C:\Tools;C:\Users\flame\.local\bin".to_owned())
        );
    }

    #[test]
    fn append_path_entry_is_case_insensitive_and_trims_separators() {
        assert_eq!(
            append_path_entry(
                r"C:\Windows;C:\Users\flame\.local\bin\;",
                r"c:/users/flame/.local/bin",
                ';',
                true
            ),
            None
        );
    }
}
