//! Serde structs for the Claude Code stdin payload.
//!
//! Every field is optional; missing fields just suppress the corresponding
//! statusline segment, mirroring the bash script's leniency.

use serde::Deserialize;

#[derive(Debug, Default, Deserialize)]
pub struct Input {
    #[serde(default)]
    pub workspace: Workspace,
    #[serde(default)]
    pub cwd: Option<String>,
    #[serde(default)]
    pub transcript_path: Option<String>,
    #[serde(default)]
    pub model: Model,
    #[serde(default)]
    pub context_window: ContextWindow,
    #[serde(default)]
    pub rate_limits: RateLimits,
    #[serde(default)]
    pub cost: Cost,
}

#[derive(Debug, Default, Deserialize)]
pub struct Workspace {
    #[serde(default)]
    pub current_dir: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
pub struct Model {
    #[serde(default)]
    pub display_name: Option<String>,
}

#[derive(Debug, Default, Deserialize)]
pub struct ContextWindow {
    #[serde(default)]
    pub used_percentage: Option<f64>,
    #[serde(default)]
    pub context_window_size: Option<u64>,
    #[serde(default)]
    pub current_usage: ContextUsage,
}

#[derive(Debug, Default, Deserialize)]
pub struct ContextUsage {
    #[serde(default)]
    pub input_tokens: u64,
    #[serde(default)]
    pub cache_creation_input_tokens: u64,
    #[serde(default)]
    pub cache_read_input_tokens: u64,
}

impl ContextUsage {
    pub const fn total(&self) -> u64 {
        self.input_tokens + self.cache_creation_input_tokens + self.cache_read_input_tokens
    }
}

#[derive(Debug, Default, Deserialize)]
pub struct RateLimits {
    #[serde(default)]
    pub five_hour: RateLimit,
    #[serde(default)]
    pub seven_day: RateLimit,
}

#[derive(Debug, Default, Deserialize)]
pub struct RateLimit {
    #[serde(default)]
    pub used_percentage: Option<f64>,
    /// Unix epoch seconds at which this window resets. When present we
    /// render a `1h 23m left` countdown next to the percentage.
    #[serde(default)]
    pub resets_at: Option<i64>,
}

/// Claude Code optionally pre-computes the session's API-equivalent cost.
///
/// Passed down on stdin. When present, mirroring ccusage's "auto" mode,
/// we prefer this number over walking the transcript ourselves.
#[derive(Debug, Default, Deserialize)]
pub struct Cost {
    #[serde(default)]
    pub total_cost_usd: Option<f64>,
    #[serde(default)]
    pub total_api_duration_ms: Option<u64>,
    #[serde(default)]
    pub total_lines_added: Option<u64>,
    #[serde(default)]
    pub total_lines_removed: Option<u64>,
}

impl Input {
    /// First non-empty path field, ignoring `Some("")` which Claude Code
    /// occasionally emits during early hook events.
    fn path_field(&self) -> Option<&str> {
        [self.workspace.current_dir.as_deref(), self.cwd.as_deref()]
            .into_iter()
            .flatten()
            .find(|s| !s.is_empty())
    }

    /// Path used as the cwd for VCS lookups (`workspace.current_dir` -> cwd
    /// -> process cwd). Substitutes the actual process cwd as a fallback so
    /// `gix::open` can resolve a real absolute path.
    pub fn vcs_dir(&self) -> String {
        if let Some(p) = self.path_field() {
            return p.to_string();
        }
        std::env::current_dir()
            .ok()
            .and_then(|p| p.to_str().map(str::to_owned))
            .unwrap_or_else(|| ".".to_string())
    }

    /// Display name for the directory segment (last path component).
    /// Falls back to the process cwd basename when Claude Code didn't
    /// supply a usable path - without this, fresh sessions render a bare
    /// `.` next to the VCS info.
    pub fn dir_name(&self) -> String {
        if let Some(p) = self.path_field() {
            return basename(p).to_string();
        }
        std::env::current_dir()
            .ok()
            .and_then(|p| {
                p.file_name()
                    .map(|n| n.to_string_lossy().into_owned())
                    .or_else(|| p.to_str().map(str::to_owned))
            })
            .unwrap_or_else(|| ".".to_string())
    }

    /// Full absolute path as Claude Code reported it. Falls back to the
    /// process cwd so fresh sessions still render something instead of
    /// a bare `.`.
    pub fn dir_full(&self) -> String {
        if let Some(p) = self.path_field() {
            return p.to_string();
        }
        std::env::current_dir()
            .ok()
            .and_then(|p| p.to_str().map(str::to_owned))
            .unwrap_or_else(|| ".".to_string())
    }

    /// Full path with the user's home directory collapsed to `~`.
    /// When the path doesn't live under home (or home isn't
    /// resolvable) we hand back the full form unchanged.
    pub fn dir_home(&self) -> String {
        let full = self.dir_full();
        let Some(home) = dirs::home_dir() else {
            return full;
        };
        let Some(home_str) = home.to_str() else {
            return full;
        };
        if home_str.is_empty() {
            return full;
        }
        if let Some(rest) = full.strip_prefix(home_str) {
            if rest.is_empty() {
                return "~".to_string();
            }
            // On Windows the separator is `\`, on Unix it's `/`. Match
            // either so the home collapse works on both without us
            // having to import `MAIN_SEPARATOR`.
            if rest.starts_with('/') || rest.starts_with('\\') {
                return format!("~{rest}");
            }
        }
        full
    }
}

fn basename(path: &str) -> &str {
    let trimmed = path.trim_end_matches('/');
    match trimmed.rsplit_once('/') {
        Some((_, last)) if !last.is_empty() => last,
        _ if !trimmed.is_empty() => trimmed,
        _ => ".",
    }
}
