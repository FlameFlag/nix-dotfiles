use std::path::Path;
use std::process::Stdio;
use std::time::Duration;

use indexmap::IndexSet;
use tokio::process::Command;
use tokio::time::timeout;

const PATH_PROBE_TIMEOUT: Duration = Duration::from_secs(5);
const PATH_MARKER_START: &str = "__SYSTEM_RUN_MCP_PATH_START__";
const PATH_MARKER_END: &str = "__SYSTEM_RUN_MCP_PATH_END__";
const SHELL_PATH_PROBE_SCRIPT: &str = "printf '%s\n' __SYSTEM_RUN_MCP_PATH_START__; printf '%s\n' \"$PATH\"; printf '%s\n' __SYSTEM_RUN_MCP_PATH_END__";

pub(crate) async fn user_shell_path() -> Option<String> {
    let home = std::env::var("HOME").ok();
    for shell in shell_probe_candidates() {
        let mut process = Command::new(&shell);
        process
            .arg(shell_probe_flag(&shell))
            .arg(SHELL_PATH_PROBE_SCRIPT)
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        if let Some(home) = home.as_deref() {
            process.env("HOME", home);
        }

        let output = match timeout(PATH_PROBE_TIMEOUT, process.output()).await {
            Ok(Ok(output)) => output,
            Ok(Err(_)) | Err(_) => continue,
        };
        if !output.status.success() {
            continue;
        }
        if let Some(path) = parse_marked_path(&output.stdout) {
            return Some(normalize_user_shell_path(&path, home.as_deref()));
        }
    }
    None
}

fn shell_probe_candidates() -> Vec<String> {
    let mut candidates = IndexSet::new();
    if let Ok(shell) = std::env::var("SHELL")
        && !shell.is_empty()
    {
        candidates.insert(shell);
    }
    candidates.extend(["/bin/zsh", "/bin/bash", "zsh", "bash", "sh"].map(str::to_owned));
    candidates.into_iter().collect()
}

fn shell_probe_flag(shell: &str) -> &'static str {
    let name = Path::new(shell)
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or(shell);
    match name {
        "bash" | "zsh" => "-lic",
        _ => "-c",
    }
}

fn normalize_user_shell_path(path: &str, home: Option<&str>) -> String {
    let Some(home) = home.filter(|home| !home.is_empty()) else {
        return path.to_owned();
    };
    let home = Path::new(home);
    let prefixes = [
        ".pi/agent/bin",
        ".bun/bin",
        ".bun/install/global/node_modules/.bin",
        ".npm/bin",
        ".local/bin",
        ".cargo/bin",
        ".go/bin",
        ".yarn/bin",
    ];
    let shell_entries = std::env::split_paths(path).collect::<Vec<_>>();
    let mut entries = IndexSet::new();
    for prefix in prefixes {
        let entry = home.join(prefix);
        if !shell_entries.iter().any(|seen| seen == &entry) {
            entries.insert(entry);
        }
    }
    entries.extend(shell_entries);
    std::env::join_paths(entries)
        .map(|entries| entries.to_string_lossy().into_owned())
        .unwrap_or_else(|_| path.to_owned())
}

fn parse_marked_path(output: &[u8]) -> Option<String> {
    let output = String::from_utf8_lossy(output);
    let (_, output) = output.split_once(PATH_MARKER_START)?;
    let output = output.strip_prefix('\n').unwrap_or(output);
    let (path, _) = output.split_once(PATH_MARKER_END)?;
    let path = path.trim_end_matches(['\r', '\n']);
    if path.is_empty() {
        None
    } else {
        Some(path.to_owned())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_marked_path_extracts_path_between_markers() {
        let output = br#"startup noise
__SYSTEM_RUN_MCP_PATH_START__
/one:/two:/three
__SYSTEM_RUN_MCP_PATH_END__
trailing noise
"#;

        assert_eq!(
            parse_marked_path(output),
            Some("/one:/two:/three".to_owned())
        );
    }

    #[test]
    fn normalize_user_shell_path_prepends_user_tool_dirs() {
        let path =
            "/Users/flame/.nix-profile/bin:/run/current-system/sw/bin:/Users/flame/.cargo/bin";

        assert_eq!(
            normalize_user_shell_path(path, Some("/Users/flame")),
            "/Users/flame/.pi/agent/bin:/Users/flame/.bun/bin:/Users/flame/.bun/install/global/node_modules/.bin:/Users/flame/.npm/bin:/Users/flame/.local/bin:/Users/flame/.go/bin:/Users/flame/.yarn/bin:/Users/flame/.nix-profile/bin:/run/current-system/sw/bin:/Users/flame/.cargo/bin"
        );
    }

    #[test]
    fn normalize_user_shell_path_preserves_complete_shell_order() {
        let path = "/home/nyx/.yarn/bin:/home/nyx/.go/bin:/home/nyx/.cargo/bin:/home/nyx/.local/bin:/home/nyx/.npm/bin:/home/nyx/.bun/install/global/node_modules/.bin:/home/nyx/.bun/bin:/home/nyx/.pi/agent/bin:/run/current-system/sw/bin";

        assert_eq!(normalize_user_shell_path(path, Some("/home/nyx")), path);
    }
}
