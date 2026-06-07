use std::path::{Path, PathBuf};

use tempfile::TempDir;
use toml_edit::{DocumentMut, Item, Table, value};

use crate::{Error, Result, detect_theme, home_dir};

use super::mcp::prune_unreachable_local_mcp_servers;

pub(super) fn create_trust_overlay() -> Result<TempDir> {
    let codex_home = codex_home()?;
    let trust_target = trust_target()?;
    let overlay_root = codex_overlay_root()?;
    let theme = detect_theme();
    create_trust_overlay_in(&codex_home, &trust_target, &overlay_root, theme.name)
}

fn create_trust_overlay_in(
    codex_home: &Path,
    trust_target: &Path,
    overlay_root: &Path,
    tui_theme: &str,
) -> Result<TempDir> {
    fs_err::create_dir_all(codex_home)?;
    fs_err::create_dir_all(overlay_root)?;
    let overlay = tempfile::Builder::new()
        .prefix("codex-trust")
        .tempdir_in(overlay_root)?;
    // Keep the real Codex state visible but write a temporary config that marks
    // only the current repository trusted for this invocation.
    symlink_home_entries(codex_home, overlay.path())?;
    write_trusted_config(codex_home, overlay.path(), trust_target, tui_theme)?;
    Ok(overlay)
}

fn codex_overlay_root() -> Result<PathBuf> {
    Ok(home_dir()?.join(".cache/zellij-theme-run/codex"))
}

fn codex_home() -> Result<PathBuf> {
    let home = home_dir()?;
    Ok(codex_home_from(std::env::var_os("CODEX_HOME"), &home))
}

fn codex_home_from(value: Option<std::ffi::OsString>, home: &Path) -> PathBuf {
    if let Some(value) = value {
        let path = PathBuf::from(value);
        if !path.as_os_str().is_empty() {
            // Nested Codex sessions inherit the wrapper's temporary overlay.
            // Use the real user config as the next overlay source instead.
            if is_trust_overlay(&path) {
                return home.join(".codex");
            }
            return expand_user(path);
        }
    }
    home.join(".codex")
}

fn is_trust_overlay(path: &Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.starts_with("codex-trust"))
}

fn expand_user(path: PathBuf) -> PathBuf {
    let text = path.to_string_lossy();
    match (text == "~", text.strip_prefix("~/")) {
        (true, _) => home_dir().unwrap_or(path),
        (false, Some(rest)) => home_dir().map_or_else(|_| path.clone(), |home| home.join(rest)),
        (false, None) => path,
    }
}

fn trust_target() -> Result<PathBuf> {
    let output = duct::cmd("git", ["rev-parse", "--show-toplevel"])
        .stdout_capture()
        .stderr_null()
        .unchecked()
        .run();
    if let Ok(output) = output
        && output.status.success()
    {
        let trimmed = String::from_utf8_lossy(&output.stdout).trim().to_owned();
        if !trimmed.is_empty() {
            return Ok(PathBuf::from(trimmed));
        }
    }
    Ok(std::env::current_dir()?)
}

fn symlink_home_entries(codex_home: &Path, overlay: &Path) -> Result<()> {
    for entry in fs_err::read_dir(codex_home)? {
        let entry = entry?;
        if entry.file_name() == "config.toml" {
            continue;
        }
        let target = overlay.join(entry.file_name());
        #[cfg(unix)]
        {
            use std::os::unix::fs::symlink;
            if symlink(entry.path(), &target).is_err() && !target.exists() {
                fs_err::copy(entry.path(), target)?;
            }
        }
        #[cfg(windows)]
        {
            if entry.path().is_dir() {
                std::os::windows::fs::symlink_dir(entry.path(), &target)?;
            } else {
                std::os::windows::fs::symlink_file(entry.path(), &target)?;
            }
        }
    }
    Ok(())
}

fn write_trusted_config(
    codex_home: &Path,
    overlay: &Path,
    trust_target: &Path,
    tui_theme: &str,
) -> Result<()> {
    let source = codex_home.join("config.toml");
    let existing = match fs_err::read_to_string(&source) {
        Ok(text) => text,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(err) => return Err(err.into()),
    };
    let updated = trusted_config(&existing, &trust_target.to_string_lossy(), tui_theme)?;
    fs_err::write(overlay.join("config.toml"), updated)?;
    Ok(())
}

fn trusted_config(existing: &str, trust_target: &str, tui_theme: &str) -> Result<String> {
    let mut doc = if existing.trim().is_empty() {
        DocumentMut::new()
    } else {
        existing.parse::<DocumentMut>()?
    };
    prune_unreachable_local_mcp_servers(&mut doc);
    ensure_project_table(&mut doc, trust_target)?;
    ensure_tui_theme(&mut doc, tui_theme)?;
    Ok(doc.to_string())
}

fn ensure_tui_theme(doc: &mut DocumentMut, tui_theme: &str) -> Result<()> {
    if !doc.as_table().contains_key("tui") {
        doc["tui"] = Item::Table(Table::new());
    }
    if doc["tui"].as_table().is_none() {
        doc["tui"] = Item::Table(Table::new());
    }
    let tui = doc["tui"].as_table_mut().ok_or(Error::InvalidCodexConfig)?;
    tui["theme"] = value(tui_theme);
    Ok(())
}

fn ensure_project_table(doc: &mut DocumentMut, trust_target: &str) -> Result<()> {
    if !doc.as_table().contains_key("projects") {
        doc["projects"] = Item::Table(Table::new());
    }
    if doc["projects"].as_table().is_none() {
        doc["projects"] = Item::Table(Table::new());
    }
    let projects = doc["projects"]
        .as_table_mut()
        .ok_or(Error::InvalidCodexConfig)?;
    if !projects.contains_key(trust_target) {
        projects.insert(trust_target, Item::Table(Table::new()));
    }
    if projects[trust_target].as_table().is_none() {
        projects.insert(trust_target, Item::Table(Table::new()));
    }
    let project = projects[trust_target]
        .as_table_mut()
        .ok_or(Error::InvalidCodexConfig)?;
    project["trust_level"] = value("trusted");
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trusted_config_appends_project_table() -> Result<()> {
        let updated = trusted_config("model = \"gpt-5.5\"\n", "/repo", "catppuccin-frappe-pink")?;
        assert!(updated.contains("[projects.\"/repo\"]"));
        assert!(updated.contains("trust_level = \"trusted\""));
        assert!(updated.contains("theme = \"catppuccin-frappe-pink\""));
        Ok(())
    }

    #[test]
    fn write_trusted_config_writes_overlay_config() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let codex_home = temp.path().join("home");
        let overlay = temp.path().join("overlay");
        fs_err::create_dir_all(&codex_home)?;
        fs_err::create_dir_all(&overlay)?;
        fs_err::write(codex_home.join("config.toml"), "model = \"gpt-5.5\"\n")?;

        write_trusted_config(
            &codex_home,
            &overlay,
            Path::new("/repo"),
            "catppuccin-latte-pink",
        )?;

        let updated = fs_err::read_to_string(overlay.join("config.toml"))?;
        assert!(updated.contains("[projects.\"/repo\"]"));
        assert!(updated.contains("trust_level = \"trusted\""));
        assert!(updated.contains("theme = \"catppuccin-latte-pink\""));
        Ok(())
    }

    #[test]
    fn symlink_home_entries_skips_config_and_links_other_entries() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let codex_home = temp.path().join("home");
        let overlay = temp.path().join("overlay");
        fs_err::create_dir_all(&codex_home)?;
        fs_err::create_dir_all(&overlay)?;
        fs_err::write(codex_home.join("config.toml"), "model = \"gpt-5.5\"\n")?;
        fs_err::write(codex_home.join("history.jsonl"), "[]\n")?;

        symlink_home_entries(&codex_home, &overlay)?;

        assert!(!overlay.join("config.toml").exists());
        let linked = overlay.join("history.jsonl");
        assert!(linked.exists());
        #[cfg(unix)]
        assert_eq!(
            fs_err::read_link(&linked)?,
            codex_home.join("history.jsonl")
        );
        Ok(())
    }

    #[test]
    fn create_trust_overlay_for_links_state_and_trusts_target() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let codex_home = temp.path().join("home");
        fs_err::create_dir_all(&codex_home)?;
        fs_err::write(codex_home.join("history.jsonl"), "[]\n")?;

        let overlay_root = temp.path().join("overlay-root");
        let overlay = create_trust_overlay_in(
            &codex_home,
            Path::new("/repo"),
            &overlay_root,
            "catppuccin-frappe-pink",
        )?;

        assert!(overlay.path().join("history.jsonl").exists());
        assert!(overlay.path().starts_with(overlay_root));
        let updated = fs_err::read_to_string(overlay.path().join("config.toml"))?;
        assert!(updated.contains("[projects.\"/repo\"]"));
        assert!(updated.contains("trust_level = \"trusted\""));
        assert!(updated.contains("theme = \"catppuccin-frappe-pink\""));
        Ok(())
    }

    #[test]
    fn trusted_config_replaces_existing_tui_theme() -> Result<()> {
        let updated = trusted_config(
            r#"
[tui]
theme = "dracula"
status_line_use_colors = true
"#,
            "/repo",
            "catppuccin-latte-pink",
        )?;

        assert!(updated.contains("theme = \"catppuccin-latte-pink\""));
        assert!(!updated.contains("theme = \"dracula\""));
        assert!(updated.contains("status_line_use_colors = true"));
        Ok(())
    }

    #[test]
    fn codex_home_ignores_inherited_trust_overlay() -> Result<()> {
        let home = PathBuf::from("/home/user");

        let inherited_overlay = std::env::temp_dir().join("codex-trustabc");
        let resolved = codex_home_from(Some(inherited_overlay.into_os_string()), &home);

        assert_eq!(resolved, PathBuf::from("/home/user/.codex"));
        Ok(())
    }

    #[test]
    fn codex_home_keeps_custom_temp_home() -> Result<()> {
        let home = PathBuf::from("/home/user");
        let custom_home = std::env::temp_dir().join("custom-codex");

        let resolved = codex_home_from(Some(custom_home.clone().into_os_string()), &home);

        assert_eq!(resolved, custom_home);
        Ok(())
    }

    #[test]
    fn trusted_config_prunes_unreachable_local_mcp_server() -> Result<()> {
        let updated = trusted_config(
            r#"
[mcp_servers.ghidra]
url = "http://127.0.0.1:1/mcp"
startup_timeout_sec = 60

[mcp_servers.remote]
url = "https://example.com/mcp"
"#,
            "/repo",
            "catppuccin-frappe-pink",
        )?;

        assert!(!updated.contains("[mcp_servers.ghidra]"));
        assert!(updated.contains("[mcp_servers.remote]"));
        assert!(updated.contains("[projects.\"/repo\"]"));
        Ok(())
    }
}
