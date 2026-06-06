use std::ffi::OsString;
use std::io::Write;
use std::path::{Path, PathBuf};

use directories::BaseDirs;

use crate::{Error, FRAPPE, LATTE, Result, Theme, detect_theme, run_inherit, wants_version_arg};

const DARK_THEME: &str = "catppuccin_frappe_pink";
const LIGHT_THEME: &str = "catppuccin_latte_pink";

/// Runs `btop-auto-theme`.
///
/// # Errors
///
/// Returns an error if config generation fails or the real btop executable
/// cannot be found or executed.
pub fn run() -> Result<i32> {
    if wants_version_arg() && std::env::var_os("BTOP_AUTO_THEME_WRAPPER").is_none() {
        println!("btop-auto-theme {}", env!("CARGO_PKG_VERSION"));
        return Ok(0);
    }

    let args: Vec<OsString> = std::env::args_os().skip(1).collect();
    let btop = find_btop()?;
    let base_config_path = config_arg(&args).unwrap_or_else(default_config_path);
    let base_config = read_base_config(&base_config_path)?;
    let theme = btop_theme_name(detect_theme());
    let themed_config = with_color_theme(&base_config, theme);

    let mut config = tempfile::Builder::new()
        .prefix("btop-auto-theme-")
        .suffix(".conf")
        .tempfile()?;
    config.write_all(themed_config.as_bytes())?;
    config.flush()?;

    let mut btop_args = Vec::with_capacity(args.len() + 2);
    btop_args.push(OsString::from("--config"));
    btop_args.push(config.path().as_os_str().to_owned());
    btop_args.extend(strip_config_args(args));

    run_inherit(&duct::cmd(btop, btop_args))
}

fn btop_theme_name(theme: Theme) -> &'static str {
    match theme.name {
        name if name == FRAPPE.name => DARK_THEME,
        name if name == LATTE.name => LIGHT_THEME,
        _ => DARK_THEME,
    }
}

fn default_config_path() -> PathBuf {
    BaseDirs::new()
        .map(|dirs| dirs.home_dir().join(".config/btop/btop.conf"))
        .unwrap_or_else(|| PathBuf::from(".config/btop/btop.conf"))
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

fn with_color_theme(config: &str, theme: &str) -> String {
    let replacement = format!("color_theme = \"{theme}\"");
    let mut changed = false;
    let mut output = String::with_capacity(config.len() + replacement.len() + 1);

    for line in config.lines() {
        if line.trim_start().starts_with("color_theme =") {
            output.push_str(&replacement);
            changed = true;
        } else {
            output.push_str(line);
        }
        output.push('\n');
    }

    if !changed {
        output.push_str(&replacement);
        output.push('\n');
    }

    output
}

fn find_btop() -> Result<PathBuf> {
    let skip = skip_paths();
    which::which_all("btop")
        .map_err(|_| Error::BtopNotFound)?
        .find(|candidate| !skip.iter().any(|path| same_path(candidate, path)))
        .ok_or(Error::BtopNotFound)
}

fn skip_paths() -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Some(wrapper) = std::env::var_os("BTOP_AUTO_THEME_WRAPPER") {
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
    fn replaces_existing_color_theme() {
        assert_eq!(
            with_color_theme(
                "foo = true\ncolor_theme = \"old\"\nbar = false\n",
                LIGHT_THEME
            ),
            "foo = true\ncolor_theme = \"catppuccin_latte_pink\"\nbar = false\n",
        );
    }

    #[test]
    fn appends_color_theme_when_missing() {
        assert_eq!(
            with_color_theme("foo = true\n", DARK_THEME),
            "foo = true\ncolor_theme = \"catppuccin_frappe_pink\"\n",
        );
    }

    #[test]
    fn strips_short_and_long_config_args() {
        let args = vec![
            OsString::from("--config"),
            OsString::from("one"),
            OsString::from("-c"),
            OsString::from("two"),
            OsString::from("--config=three"),
            OsString::from("--preset"),
            OsString::from("1"),
        ];
        assert_eq!(
            strip_config_args(args),
            vec![OsString::from("--preset"), OsString::from("1")],
        );
    }
}
