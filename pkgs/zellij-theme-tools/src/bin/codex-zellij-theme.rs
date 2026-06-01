use tempfile::TempDir;
use toml_edit::{DocumentMut, Item, Table, value};
use url::Url;
use zellij_theme_tools::{
    Error, Result, codex_bin, detect_system_theme, detect_terminal_theme, home_dir,
    reset_pane_color, run_inherit, send_focus_gained, write_pane_color_override,
};

const MCP_CONNECT_TIMEOUT: std::time::Duration = std::time::Duration::from_millis(150);

fn main() {
    match run() {
        Ok(code) => std::process::exit(code),
        Err(err) => {
            eprintln!("error: {err}");
            std::process::exit(1);
        }
    }
}

fn run() -> Result<i32> {
    if wants_version() {
        println!("codex-zellij-theme {}", env!("CARGO_PKG_VERSION"));
        return Ok(0);
    }

    let _startup_pane_color = StartupPaneColor::start();

    let overlay = create_trust_overlay()?;
    let codex = codex_bin()?;
    let command = duct::cmd(codex, std::env::args_os().skip(1))
        .env("CODEX_HOME", overlay.path())
        .unchecked();
    run_inherit(&command)
}

fn wants_version() -> bool {
    std::env::args_os()
        .skip(1)
        .any(|arg| arg == "--version" || arg == "-V")
}

struct StartupPaneColor {
    enabled: bool,
}

impl StartupPaneColor {
    fn start() -> Self {
        let enabled = std::env::var_os("ZELLIJ").is_some() && which::which("zellij").is_ok();
        if enabled {
            let theme = detect_terminal_theme().unwrap_or_else(detect_system_theme);
            write_pane_color_override(theme.colors);
            let pane_id = std::env::var("ZELLIJ_PANE_ID").ok();
            let _ = std::thread::Builder::new()
                .name("zellij-pane-color-reset".to_owned())
                .spawn(move || {
                    if let Some(pane_id) = pane_id {
                        for _ in 0..3 {
                            std::thread::sleep(std::time::Duration::from_millis(500));
                            send_focus_gained(&pane_id);
                        }
                        std::thread::sleep(std::time::Duration::from_millis(1500));
                    } else {
                        std::thread::sleep(std::time::Duration::from_secs(3));
                    }
                    reset_pane_color();
                });
        }
        Self { enabled }
    }
}

impl Drop for StartupPaneColor {
    fn drop(&mut self) {
        if self.enabled {
            reset_pane_color();
        }
    }
}

fn create_trust_overlay() -> Result<TempDir> {
    let codex_home = codex_home()?;
    let trust_target = trust_target()?;
    let overlay_root = codex_overlay_root()?;
    create_trust_overlay_in(&codex_home, &trust_target, &overlay_root)
}

fn create_trust_overlay_in(
    codex_home: &std::path::Path,
    trust_target: &std::path::Path,
    overlay_root: &std::path::Path,
) -> Result<TempDir> {
    fs_err::create_dir_all(codex_home)?;
    fs_err::create_dir_all(overlay_root)?;
    let overlay = tempfile::Builder::new()
        .prefix("codex-trust")
        .tempdir_in(overlay_root)?;
    // Keep the real Codex state visible but write a temporary config that marks
    // only the current repository trusted for this invocation.
    symlink_home_entries(codex_home, overlay.path())?;
    write_trusted_config(codex_home, overlay.path(), trust_target)?;
    Ok(overlay)
}

fn codex_overlay_root() -> Result<std::path::PathBuf> {
    Ok(home_dir()?.join(".cache/codex-zellij-theme"))
}

fn codex_home() -> Result<std::path::PathBuf> {
    codex_home_from(std::env::var_os("CODEX_HOME"), home_dir()?)
}

fn codex_home_from(
    value: Option<std::ffi::OsString>,
    home: std::path::PathBuf,
) -> Result<std::path::PathBuf> {
    if let Some(value) = value {
        let path = std::path::PathBuf::from(value);
        if !path.as_os_str().is_empty() {
            // Nested Codex sessions inherit the wrapper's temporary overlay.
            // Use the real user config as the next overlay source instead.
            if is_trust_overlay(&path) {
                return Ok(home.join(".codex"));
            }
            return Ok(expand_user(path));
        }
    }
    Ok(home.join(".codex"))
}

fn is_trust_overlay(path: &std::path::Path) -> bool {
    path.file_name()
        .and_then(|name| name.to_str())
        .is_some_and(|name| name.starts_with("codex-trust"))
}

fn expand_user(path: std::path::PathBuf) -> std::path::PathBuf {
    let text = path.to_string_lossy();
    match (text == "~", text.strip_prefix("~/")) {
        (true, _) => home_dir().unwrap_or(path),
        (false, Some(rest)) => home_dir().map_or_else(|_| path.clone(), |home| home.join(rest)),
        (false, None) => path,
    }
}

fn trust_target() -> Result<std::path::PathBuf> {
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
            return Ok(std::path::PathBuf::from(trimmed));
        }
    }
    Ok(std::env::current_dir()?)
}

fn symlink_home_entries(codex_home: &std::path::Path, overlay: &std::path::Path) -> Result<()> {
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
    codex_home: &std::path::Path,
    overlay: &std::path::Path,
    trust_target: &std::path::Path,
) -> Result<()> {
    let source = codex_home.join("config.toml");
    let existing = match fs_err::read_to_string(&source) {
        Ok(text) => text,
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => String::new(),
        Err(err) => return Err(err.into()),
    };
    let updated = trusted_config(&existing, &trust_target.to_string_lossy())?;
    fs_err::write(overlay.join("config.toml"), updated)?;
    Ok(())
}

fn trusted_config(existing: &str, trust_target: &str) -> Result<String> {
    let mut doc = if existing.trim().is_empty() {
        DocumentMut::new()
    } else {
        existing.parse::<DocumentMut>()?
    };
    prune_unreachable_local_mcp_servers(&mut doc);
    if !doc.as_table().contains_key("projects") {
        doc["projects"] = Item::Table(Table::new());
    }
    if doc["projects"].as_table().is_none() {
        doc["projects"] = Item::Table(Table::new());
    }
    // Existing configs can contain malformed or non-table project entries; keep
    // the rest of the file intact while normalizing the shape Codex expects.
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
    Ok(doc.to_string())
}

fn prune_unreachable_local_mcp_servers(doc: &mut DocumentMut) {
    if !mcp_pruning_enabled() {
        return;
    }

    let Some(servers) = doc["mcp_servers"].as_table_mut() else {
        return;
    };
    let unreachable_servers = servers
        .iter()
        .filter_map(|(name, item)| {
            let url = item.get("url")?.as_str()?;
            if local_mcp_url_is_unreachable(url) {
                Some(name.to_owned())
            } else {
                None
            }
        })
        .collect::<Vec<_>>();

    for name in unreachable_servers {
        servers.remove(&name);
    }
}

fn mcp_pruning_enabled() -> bool {
    std::env::var("CODEX_ZELLIJ_THEME_PRUNE_UNREACHABLE_MCP")
        .map(|value| {
            let value = value.trim();
            !value.eq_ignore_ascii_case("0") && !value.eq_ignore_ascii_case("false")
        })
        .unwrap_or(true)
}

fn local_mcp_url_is_unreachable(raw: &str) -> bool {
    let Some((host, port)) = local_http_endpoint(raw) else {
        return false;
    };
    !tcp_endpoint_is_reachable(&host, port)
}

fn local_http_endpoint(raw: &str) -> Option<(String, u16)> {
    let url = Url::parse(raw).ok()?;
    if !matches!(url.scheme(), "http" | "https") {
        return None;
    }
    let host = url.host_str()?;
    if !host_is_loopback(host) {
        return None;
    }
    Some((host.to_owned(), url.port_or_known_default()?))
}

fn host_is_loopback(host: &str) -> bool {
    host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::IpAddr>()
            .is_ok_and(|addr| addr.is_loopback())
}

fn tcp_endpoint_is_reachable(host: &str, port: u16) -> bool {
    use std::net::{TcpStream, ToSocketAddrs};

    let Ok(addrs) = (host, port).to_socket_addrs() else {
        return false;
    };
    addrs
        .into_iter()
        .any(|addr| TcpStream::connect_timeout(&addr, MCP_CONNECT_TIMEOUT).is_ok())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn trusted_config_appends_project_table() -> Result<()> {
        let updated = trusted_config("model = \"gpt-5.5\"\n", "/repo")?;
        assert!(updated.contains("[projects.\"/repo\"]"));
        assert!(updated.contains("trust_level = \"trusted\""));
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

        write_trusted_config(&codex_home, &overlay, std::path::Path::new("/repo"))?;

        let updated = fs_err::read_to_string(overlay.join("config.toml"))?;
        assert!(updated.contains("[projects.\"/repo\"]"));
        assert!(updated.contains("trust_level = \"trusted\""));
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
        let overlay =
            create_trust_overlay_in(&codex_home, std::path::Path::new("/repo"), &overlay_root)?;

        assert!(overlay.path().join("history.jsonl").exists());
        assert!(overlay.path().starts_with(overlay_root));
        let updated = fs_err::read_to_string(overlay.path().join("config.toml"))?;
        assert!(updated.contains("[projects.\"/repo\"]"));
        assert!(updated.contains("trust_level = \"trusted\""));
        Ok(())
    }

    #[test]
    fn codex_home_ignores_inherited_trust_overlay() -> Result<()> {
        let home = std::path::PathBuf::from("/home/user");

        let inherited_overlay = std::env::temp_dir().join("codex-trustabc");
        let resolved = codex_home_from(Some(inherited_overlay.into_os_string()), home)?;

        assert_eq!(resolved, std::path::PathBuf::from("/home/user/.codex"));
        Ok(())
    }

    #[test]
    fn codex_home_keeps_custom_temp_home() -> Result<()> {
        let home = std::path::PathBuf::from("/home/user");
        let custom_home = std::env::temp_dir().join("custom-codex");

        let resolved = codex_home_from(Some(custom_home.clone().into_os_string()), home)?;

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
        )?;

        assert!(!updated.contains("[mcp_servers.ghidra]"));
        assert!(updated.contains("[mcp_servers.remote]"));
        assert!(updated.contains("[projects.\"/repo\"]"));
        Ok(())
    }

    #[test]
    fn local_http_endpoint_accepts_loopback_hosts_only() {
        assert_eq!(
            local_http_endpoint("http://127.0.0.1:8090/mcp"),
            Some(("127.0.0.1".to_owned(), 8090))
        );
        assert_eq!(
            local_http_endpoint("http://localhost:8090/mcp"),
            Some(("localhost".to_owned(), 8090))
        );
        assert_eq!(local_http_endpoint("https://example.com/mcp"), None);
    }
}
