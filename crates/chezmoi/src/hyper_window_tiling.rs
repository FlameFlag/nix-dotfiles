use std::ffi::OsString;
use std::path::{Path, PathBuf};

use crate::command;
use crate::context::{Options, Os, context_with_options, os_with_options};
use crate::error::{Error, Result};
use dotfiles_common::process;

const GNOME_ATTR: &str = "hyper-window-tiling-gnome";
const KDE_ATTR: &str = "hyper-window-tiling-kde";
const GNOME_EXTENSION_UUID: &str = "hyper-window-tiling@flame.local";
const GNOME_SCHEMA: &str = "org.gnome.shell.extensions.hyper-window-tiling";
const KDE_PLUGIN_ID: &str = "hyper-window-tiling";

pub fn install_hyper_window_tiling(options: &Options) -> Result<()> {
    if os_with_options(options) != Os::Linux {
        return Ok(());
    }

    if is_nixos() {
        eprintln!("info: NixOS host detected; hyper window tiling is managed by NixOS modules");
        return Ok(());
    }

    if process::path_of("nix").is_none() {
        eprintln!("warn: nix is not available; skipping hyper window tiling install");
        return Ok(());
    }

    let ctx = context_with_options(options)?;
    let repo_dir = flake_repo_dir(&ctx.source_dir)?;
    let state_dir = state_home(&ctx.home_dir).join("nix-dotfiles/hyper-window-tiling");
    let data_dir = data_home(&ctx.home_dir);
    let mut installed = false;

    if is_gnome_installed() {
        let package = build_package(&repo_dir, &state_dir, GNOME_ATTR)?;
        install_gnome(&package, &data_dir)?;
        installed = true;
    }

    if is_kde_installed() {
        let package = build_package(&repo_dir, &state_dir, KDE_ATTR)?;
        install_kde(&package, &data_dir)?;
        installed = true;
    }

    if !installed {
        eprintln!(
            "info: neither GNOME nor KDE Plasma appears to be installed; skipping hyper window tiling"
        );
    }

    Ok(())
}

fn build_package(repo_dir: &Path, state_dir: &Path, attr: &str) -> Result<PathBuf> {
    fs_err::create_dir_all(state_dir)?;
    let out_link = state_dir.join(attr);
    command::run_command(&process::argv([
        "nix",
        "--extra-experimental-features",
        "nix-command flakes",
        "build",
        "--out-link",
        &out_link.to_string_lossy(),
        &format!("{}#{attr}", repo_dir.display()),
    ]))?;
    Ok(fs_err::canonicalize(out_link)?)
}

fn install_gnome(package: &Path, data_dir: &Path) -> Result<()> {
    let source = package
        .join("share/gnome-shell/extensions")
        .join(GNOME_EXTENSION_UUID);
    let destination = data_dir
        .join("gnome-shell/extensions")
        .join(GNOME_EXTENSION_UUID);
    replace_with_symlink(&source, &destination)?;

    let schema_dir = destination.join("schemas");
    set_gnome_key(&schema_dir, "move-up", "['<Super><Control><Alt><Shift>w']");
    set_gnome_key(
        &schema_dir,
        "move-left",
        "['<Super><Control><Alt><Shift>a']",
    );
    set_gnome_key(
        &schema_dir,
        "move-down",
        "['<Super><Control><Alt><Shift>s']",
    );
    set_gnome_key(
        &schema_dir,
        "move-right",
        "['<Super><Control><Alt><Shift>d']",
    );
    set_gnome_key(
        &schema_dir,
        "move-max-almost",
        "['<Super><Control><Alt><Shift>Return']",
    );
    set_gnome_key(
        &schema_dir,
        "move-max",
        "['<Super><Control><Alt><Shift>backslash']",
    );

    run_optional(&process::argv([
        "gnome-extensions",
        "enable",
        GNOME_EXTENSION_UUID,
    ]));

    eprintln!("success: GNOME hyper window tiling extension installed");
    Ok(())
}

fn install_kde(package: &Path, data_dir: &Path) -> Result<()> {
    let source = package
        .join("share/kwin-wayland/scripts")
        .join(KDE_PLUGIN_ID);

    if !install_kde_with_kpackage(&source) {
        replace_with_symlink(&source, &data_dir.join("kwin/scripts").join(KDE_PLUGIN_ID))?;
        replace_with_symlink(
            &source,
            &data_dir.join("kwin-wayland/scripts").join(KDE_PLUGIN_ID),
        )?;
    }

    run_first_available(
        &["kwriteconfig6", "kwriteconfig5"],
        &[
            "--file",
            "kwinrc",
            "--group",
            "Plugins",
            "--key",
            "hyper-window-tilingEnabled",
            "true",
        ],
    );
    run_first_available(
        &["qdbus6", "qdbus"],
        &["org.kde.KWin", "/KWin", "reconfigure"],
    );

    eprintln!("success: KDE hyper window tiling script installed");
    Ok(())
}

fn install_kde_with_kpackage(source: &Path) -> bool {
    let Some(kpackagetool) = process::path_of("kpackagetool6")
        .or_else(|| process::path_of("kpackagetool5"))
        .map(|path| path.to_string_lossy().into_owned())
    else {
        return false;
    };

    let source = source.to_string_lossy();
    let upgrade = process::argv([&kpackagetool, "--type", "KWin/Script", "--upgrade", &source]);
    if command::command_output(&upgrade).is_ok_and(|output| output.succeeded()) {
        return true;
    }

    let install = process::argv([&kpackagetool, "--type", "KWin/Script", "--install", &source]);
    command::command_output(&install).is_ok_and(|output| output.succeeded())
}

fn set_gnome_key(schema_dir: &Path, key: &str, value: &str) {
    if process::path_of("gsettings").is_none() {
        return;
    }

    let output = process::run_with_env(
        &process::argv(["gsettings", "set", GNOME_SCHEMA, key, value]),
        [("GSETTINGS_SCHEMA_DIR", schema_dir.as_os_str())],
    );
    if output.is_err() && has_session_bus() {
        eprintln!("warn: failed to set GNOME hyper window tiling key {key}");
    }
}

fn run_first_available(programs: &[&str], arguments: &[&str]) {
    let Some(program) = programs.iter().find_map(|program| {
        process::path_of(program).map(|path| path.to_string_lossy().into_owned())
    }) else {
        return;
    };

    let argv = std::iter::once(program.as_str())
        .chain(arguments.iter().copied())
        .collect::<Vec<&str>>();
    run_optional(&process::argv(argv));
}

fn run_optional(argv: &[String]) {
    if argv
        .first()
        .and_then(|program| process::path_of(program))
        .is_some()
    {
        let _ = command::command_output(argv);
    }
}

fn replace_with_symlink(source: &Path, destination: &Path) -> Result<()> {
    if !source.is_dir() {
        return Err(Error::CommandFailed(format!(
            "missing package directory {}",
            source.display()
        )));
    }

    if let Some(parent) = destination.parent() {
        fs_err::create_dir_all(parent)?;
    }

    match fs_err::symlink_metadata(destination) {
        Ok(metadata) if metadata.file_type().is_symlink() || metadata.is_file() => {
            fs_err::remove_file(destination)?;
        }
        Ok(metadata) if metadata.is_dir() => {
            fs_err::remove_dir_all(destination)?;
        }
        Ok(_) => {
            fs_err::remove_file(destination)?;
        }
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
        Err(err) => return Err(err.into()),
    }

    symlink_dir(source, destination)?;
    Ok(())
}

#[cfg(unix)]
fn symlink_dir(source: &Path, destination: &Path) -> std::io::Result<()> {
    std::os::unix::fs::symlink(source, destination)
}

#[cfg(not(unix))]
fn symlink_dir(source: &Path, destination: &Path) -> std::io::Result<()> {
    let _ = (source, destination);
    Err(std::io::Error::new(
        std::io::ErrorKind::Unsupported,
        "directory symlinks are only supported by this helper on Unix",
    ))
}

fn flake_repo_dir(source_dir: &Path) -> Result<PathBuf> {
    for path in source_dir.ancestors() {
        if path.join("flake.nix").is_file()
            && path.join("packages/hyper-window-tiling.nix").is_file()
        {
            return Ok(path.to_path_buf());
        }
    }

    Err(Error::CommandFailed(format!(
        "could not find flake root from {}",
        source_dir.display()
    )))
}

fn data_home(home_dir: &Path) -> PathBuf {
    env_path("XDG_DATA_HOME").unwrap_or_else(|| home_dir.join(".local/share"))
}

fn state_home(home_dir: &Path) -> PathBuf {
    env_path("XDG_STATE_HOME").unwrap_or_else(|| home_dir.join(".local/state"))
}

fn env_path(name: &str) -> Option<PathBuf> {
    std::env::var_os(name)
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty())
}

fn is_nixos() -> bool {
    let Ok(os_release) = fs_err::read_to_string("/etc/os-release") else {
        return false;
    };

    os_release.lines().any(|line| {
        let Some((name, value)) = line.split_once('=') else {
            return false;
        };
        matches!(name, "ID" | "ID_LIKE")
            && value
                .trim_matches('"')
                .split_ascii_whitespace()
                .any(|item| item == "nixos")
    })
}

fn is_gnome_installed() -> bool {
    desktop_env_contains("gnome")
        || process::path_of("gnome-shell").is_some()
        || Path::new("/usr/share/gnome-shell").is_dir()
        || Path::new("/usr/share/wayland-sessions/gnome.desktop").is_file()
}

fn is_kde_installed() -> bool {
    desktop_env_contains("kde")
        || desktop_env_contains("plasma")
        || process::path_of("kwin_wayland").is_some()
        || process::path_of("plasmashell").is_some()
        || Path::new("/usr/share/plasma").is_dir()
        || Path::new("/usr/share/wayland-sessions/plasma.desktop").is_file()
}

fn desktop_env_contains(needle: &str) -> bool {
    ["XDG_CURRENT_DESKTOP", "DESKTOP_SESSION", "GDMSESSION"]
        .into_iter()
        .filter_map(std::env::var_os)
        .map(lowercase_os_string)
        .any(|value| value.split([':', ';']).any(|part| part.contains(needle)))
}

fn lowercase_os_string(value: OsString) -> String {
    value.to_string_lossy().to_ascii_lowercase()
}

fn has_session_bus() -> bool {
    std::env::var_os("DBUS_SESSION_BUS_ADDRESS").is_some()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn finds_repo_root_above_dotfiles_source() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let dotfiles = temp.path().join("dotfiles");
        fs_err::create_dir_all(temp.path().join("packages"))?;
        fs_err::create_dir_all(&dotfiles)?;
        fs_err::write(temp.path().join("flake.nix"), "")?;
        fs_err::write(temp.path().join("packages/hyper-window-tiling.nix"), "")?;

        assert_eq!(flake_repo_dir(&dotfiles)?, temp.path());
        Ok(())
    }

    #[test]
    fn desktop_env_matching_is_case_insensitive_and_separator_aware() {
        let value = lowercase_os_string(OsString::from("ubuntu:GNOME"));

        assert!(value.split([':', ';']).any(|part| part.contains("gnome")));
    }
}
