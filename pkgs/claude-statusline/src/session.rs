//! Per-session "flash" state: remembers the last-observed cost, diff,
//! and context values so the next render can briefly highlight what's
//! new.
//!
//! Every session gets its own file so parallel `claude` instances
//! (one per terminal) never trample each other's history.
//!
//! The session key is the transcript's file stem - the UUID-like name
//! Claude Code writes to `~/.claude/projects/<dir>/<uuid>.jsonl`. If
//! there's no transcript path (tests, invocations without stdin) we
//! skip state tracking and return empty deltas.
//!
//! The "flash" window is wall-clock: when we observe a fresh delta we
//! stamp `delta_at = now`, and subsequent renders keep showing the same
//! delta until `FLASH_TTL_SECS` have passed. That way a user who types
//! a follow-up turn within ~30s still sees the change from the previous
//! turn, but the indicator fades during an idle stretch.

use std::fs;
use std::path::PathBuf;
use std::time::{SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};

/// Default wall-clock window during which a recorded delta stays
/// visible.
///
/// Long enough to catch a follow-up turn, short enough that
/// leaving the terminal idle for a minute clears the highlight.
/// Callers override this via the `flash_ttl_secs` parameter on
/// [`update`]; the value lives here so the
/// [`Settings`](crate::settings::Settings) default and the on-disk state agree
/// on a baseline.
pub const DEFAULT_FLASH_TTL_SECS: u64 = 30;

/// On-disk shape. `serde(default)` everywhere so a missing field (older
/// file, partial write, hand-editing) degrades to zero rather than
/// poisoning the whole record.
#[derive(Debug, Default, Clone, Serialize, Deserialize)]
pub struct SessionState {
    #[serde(default)]
    pub cost_usd: f64,
    #[serde(default)]
    pub lines_added: u64,
    #[serde(default)]
    pub lines_removed: u64,
    #[serde(default)]
    pub context_tokens: u64,

    // Most-recent observed delta and the wall-clock time we saw it.
    #[serde(default)]
    pub delta_cost_usd: f64,
    #[serde(default)]
    pub delta_lines_added: u64,
    #[serde(default)]
    pub delta_lines_removed: u64,
    #[serde(default)]
    pub delta_context_tokens: u64,
    #[serde(default)]
    pub delta_at: u64,
}

/// Deltas to display on the current render. `is_empty()` short-circuits
/// rendering when nothing's worth flashing.
#[derive(Debug, Default, Clone, Copy)]
pub struct Deltas {
    pub cost_usd: f64,
    pub lines_added: u64,
    pub lines_removed: u64,
    pub context_tokens: u64,
}

impl Deltas {
    pub fn is_cost(&self) -> bool {
        self.cost_usd > 0.0
    }
    pub const fn is_diff(&self) -> bool {
        self.lines_added > 0 || self.lines_removed > 0
    }
    pub const fn is_context(&self) -> bool {
        self.context_tokens > 0
    }
}

/// Derive the isolation key for a session from its transcript path.
///
/// Returns `None` when there's no usable transcript - in that case we
/// skip all state tracking so tests and ad-hoc invocations don't pollute
/// each other's history.
pub fn session_key(transcript_path: Option<&str>) -> Option<String> {
    let p = std::path::Path::new(transcript_path?);
    let stem = p.file_stem()?.to_string_lossy();
    if stem.is_empty() {
        return None;
    }
    Some(stem.into_owned())
}

fn state_path(key: &str) -> Option<PathBuf> {
    // `dirs::cache_dir` resolves to the right place on every platform
    // we ship to (XDG on Linux, `~/Library/Caches` on macOS,
    // `%LOCALAPPDATA%` on Windows).
    Some(
        dirs::cache_dir()?
            .join("claude-statusline")
            .join("sessions")
            .join(format!("{key}.json")),
    )
}

fn load(key: &str) -> SessionState {
    let Some(path) = state_path(key) else {
        return SessionState::default();
    };
    let Ok(bytes) = fs::read(&path) else {
        return SessionState::default();
    };
    serde_json::from_slice(&bytes).unwrap_or_default()
}

fn save(key: &str, state: &SessionState) {
    let Some(path) = state_path(key) else { return };
    let Some(parent) = path.parent() else { return };
    let _ = fs::create_dir_all(parent);
    let Ok(json) = serde_json::to_vec(state) else {
        return;
    };
    let Ok(tmp) = tempfile::NamedTempFile::new_in(parent) else {
        return;
    };
    if fs::write(tmp.path(), json).is_ok() {
        let _ = tmp.persist(&path);
    }
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// Update the on-disk snapshot with the values from the current render
/// and return the deltas that should flash.
///
/// When nothing has changed but the last delta is still in its flash
/// window, we re-emit the stored delta so the indicator persists across
/// renders.
///
/// `None` for any value means "no data in current render" - we carry
/// the previous snapshot's value forward instead of treating it as zero.
pub fn update(
    key: Option<&str>,
    cost: Option<f64>,
    lines_added: Option<u64>,
    lines_removed: Option<u64>,
    context_tokens: Option<u64>,
    flash_ttl_secs: u64,
) -> Deltas {
    let Some(key) = key else {
        return Deltas::default();
    };

    let mut state = load(key);
    let now = now_unix();

    // When the current render has no value for a field (e.g. cost can't
    // be computed), keep the previous snapshot's value so a flash isn't
    // faked out by a single-frame dropout.
    let new_cost = cost.unwrap_or(state.cost_usd);
    let new_la = lines_added.unwrap_or(state.lines_added);
    let new_lr = lines_removed.unwrap_or(state.lines_removed);
    let new_ctx = context_tokens.unwrap_or(state.context_tokens);

    // Only positive deltas are interesting: cost and line diffs are
    // monotonic, and context tokens can dip after `/compact` but we
    // don't want "-2k" in the flash. `max(0.0)` / `saturating_sub`
    // collapses any regression to no-op.
    let d_cost = (new_cost - state.cost_usd).max(0.0);
    let d_la = new_la.saturating_sub(state.lines_added);
    let d_lr = new_lr.saturating_sub(state.lines_removed);
    let d_ctx = new_ctx.saturating_sub(state.context_tokens);
    let any_fresh = d_cost > 0.0 || d_la > 0 || d_lr > 0 || d_ctx > 0;

    let deltas = if any_fresh {
        // Fresh change: record the observation as the new flash anchor.
        state.delta_cost_usd = d_cost;
        state.delta_lines_added = d_la;
        state.delta_lines_removed = d_lr;
        state.delta_context_tokens = d_ctx;
        state.delta_at = now;
        Deltas {
            cost_usd: d_cost,
            lines_added: d_la,
            lines_removed: d_lr,
            context_tokens: d_ctx,
        }
    } else if now.saturating_sub(state.delta_at) < flash_ttl_secs {
        // No change this render, but the last delta is still inside its
        // flash window - re-emit so the indicator persists.
        Deltas {
            cost_usd: state.delta_cost_usd,
            lines_added: state.delta_lines_added,
            lines_removed: state.delta_lines_removed,
            context_tokens: state.delta_context_tokens,
        }
    } else {
        // Flash window elapsed; clear so the next fresh delta starts clean.
        state.delta_cost_usd = 0.0;
        state.delta_lines_added = 0;
        state.delta_lines_removed = 0;
        state.delta_context_tokens = 0;
        Deltas::default()
    };

    state.cost_usd = new_cost;
    state.lines_added = new_la;
    state.lines_removed = new_lr;
    state.context_tokens = new_ctx;
    save(key, &state);

    deltas
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_key_uses_transcript_stem() {
        assert_eq!(
            session_key(Some("/Users/foo/.claude/projects/bar/abc-123.jsonl")).as_deref(),
            Some("abc-123")
        );
        assert_eq!(session_key(None), None);
        assert_eq!(session_key(Some("")), None);
    }

    #[test]
    fn deltas_flag_helpers() {
        let d = Deltas {
            cost_usd: 0.05,
            ..Default::default()
        };
        assert!(d.is_cost());
        assert!(!d.is_diff());
        assert!(!d.is_context());
    }
}
