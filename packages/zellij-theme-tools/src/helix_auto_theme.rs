use std::ffi::OsString;
use std::io::Write;
use std::path::{Path, PathBuf};

use directories::BaseDirs;
use toml_edit::{DocumentMut, value};

use crate::{Error, FRAPPE, LATTE, Result, Theme, detect_theme, run_inherit};

const DARK_THEME: &str = "catppuccin_frappe_pink";
const LIGHT_THEME: &str = "catppuccin_latte_pink";

/// Runs the Helix profile for `zellij-theme-run`.
///
/// # Errors
///
/// Returns an error if config generation fails or the real Helix executable
/// cannot be found or executed.
pub fn run_with_args(args: Vec<OsString>) -> Result<i32> {
    let helix = find_helix()?;
    let base_config_path = config_arg(&args).unwrap_or_else(default_config_path);
    let base_config = read_base_config(&base_config_path)?;
    let theme = helix_theme_name(detect_theme());
    let themed_config = with_theme(&base_config, theme)?;

    let mut config = tempfile::Builder::new()
        .prefix("zellij-theme-run-helix-")
        .suffix(".toml")
        .tempfile()?;
    config.write_all(themed_config.as_bytes())?;
    config.flush()?;

    let mut helix_args = Vec::with_capacity(args.len() + 2);
    helix_args.push(OsString::from("--config"));
    helix_args.push(config.path().as_os_str().to_owned());
    helix_args.extend(strip_config_args(args));

    run_inherit(&duct::cmd(helix, helix_args))
}

fn default_config_path() -> PathBuf {
    BaseDirs::new()
        .map(|dirs| dirs.home_dir().join(".config/helix/config.toml"))
        .unwrap_or_else(|| PathBuf::from(".config/helix/config.toml"))
}

fn read_base_config(path: &Path) -> Result<String> {
    match fs_err::read_to_string(path) {
        Ok(config) => Ok(config),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(String::new()),
        Err(err) => Err(err.into()),
    }
}

fn config_arg(args: &[OsString]) -> Option<PathBuf> {
    let mut args = args.iter();
    while let Some(arg) = args.next() {
        if arg == "--config" || arg == "-c" {
            return args.next().map(PathBuf::from);
        }
        if let Some(value) = arg.to_string_lossy().strip_prefix("--config=") {
            return Some(PathBuf::from(value));
        }
    }
    None
}

fn strip_config_args(args: Vec<OsString>) -> Vec<OsString> {
    let mut stripped = Vec::with_capacity(args.len());
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        if arg == "--config" || arg == "-c" {
            let _ = args.next();
            continue;
        }
        if arg.to_string_lossy().starts_with("--config=") {
            continue;
        }
        stripped.push(arg);
    }
    stripped
}

fn helix_theme_name(theme: Theme) -> &'static str {
    match theme.name {
        name if name == FRAPPE.name => DARK_THEME,
        name if name == LATTE.name => LIGHT_THEME,
        _ => DARK_THEME,
    }
}

fn with_theme(config: &str, theme: &str) -> Result<String> {
    let mut doc = if config.trim().is_empty() {
        DocumentMut::new()
    } else {
        config.parse::<DocumentMut>()?
    };
    doc["theme"] = value(theme);
    Ok(doc.to_string())
}

fn find_helix() -> Result<PathBuf> {
    let skip = skip_paths();
    which::which_all("hx")
        .or_else(|_| which::which_all("helix"))
        .map_err(|_| Error::HelixNotFound)?
        .find(|candidate| !skip.iter().any(|path| same_path(candidate, path)))
        .ok_or(Error::HelixNotFound)
}

fn skip_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(wrapper) = std::env::var_os("ZELLIJ_THEME_RUN_WRAPPER")
        .or_else(|| std::env::var_os("HELIX_AUTO_THEME_WRAPPER"))
    {
        paths.push(PathBuf::from(wrapper));
    }
    if let Ok(exe) = std::env::current_exe() {
        paths.push(exe);
    }
    paths
}

fn same_path(left: &Path, right: &Path) -> bool {
    if left == right {
        return true;
    }
    match (fs_err::canonicalize(left), fs_err::canonicalize(right)) {
        (Ok(left), Ok(right)) => left == right,
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn replaces_existing_theme() -> Result<()> {
        assert_eq!(
            with_theme(
                "theme = \"dracula\"\n\n[editor]\nline-number = \"relative\"\n",
                LIGHT_THEME
            )?,
            "theme = \"catppuccin_latte_pink\"\n\n[editor]\nline-number = \"relative\"\n",
        );
        Ok(())
    }

    #[test]
    fn appends_theme_when_missing() -> Result<()> {
        assert_eq!(
            with_theme("[editor]\nmouse = true\n", DARK_THEME)?,
            "theme = \"catppuccin_frappe_pink\"\n[editor]\nmouse = true\n",
        );
        Ok(())
    }

    #[test]
    fn creates_config_when_base_config_is_missing() -> Result<()> {
        assert_eq!(
            with_theme("", LIGHT_THEME)?,
            "theme = \"catppuccin_latte_pink\"\n",
        );
        Ok(())
    }

    #[test]
    fn strips_short_and_long_config_args() {
        let args = vec![
            OsString::from("--config"),
            OsString::from("one"),
            OsString::from("-c"),
            OsString::from("two"),
            OsString::from("--config=three"),
            OsString::from("--health"),
            OsString::from("all"),
        ];
        assert_eq!(
            strip_config_args(args),
            vec![OsString::from("--health"), OsString::from("all")],
        );
    }
}
