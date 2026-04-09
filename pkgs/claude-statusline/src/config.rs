//! Layout configuration loading.
//!
//! Resolution order (first non-empty wins):
//!
//! 1. `--layout` CLI flag (or `CLAUDE_STATUSLINE_LAYOUT` env var)
//! 2. `--config` file (or `CLAUDE_STATUSLINE_CONFIG` env var)
//! 3. `$XDG_CONFIG_HOME/claude-statusline/layout` (or `$HOME/.config/...`)
//! 4. Built-in [`Layout::two_line`] default
//!
//! The on-disk file is plain text containing the same DSL accepted by
//! the CLI flag - no TOML, no JSON, no parser dependency. Lines are
//! separated by either `|` or actual newlines, segments by `,`. The
//! file may contain comments starting with `#`; everything from `#` to
//! the next newline is stripped before parsing.

use std::path::{Path, PathBuf};

use crate::render::layout::{Layout, SegmentName};

/// Resolve the layout the user wants.
///
/// - `cli_layout` is the value of `--layout` (already populated from
///   `CLAUDE_STATUSLINE_LAYOUT` by clap).
/// - `cli_config` is an explicit `--config <path>`; when set we read it instead
///   of the default XDG location.
/// - `excludes` are segment names from `--exclude` to drop from whichever layout
///   we end up with.
///
/// On any parse failure we silently fall back to the default - the
/// statusline must never blank out.
pub fn load(cli_layout: Option<&str>, cli_config: Option<&Path>, excludes: &[String]) -> Layout {
    let mut layout = resolve_base(cli_layout, cli_config);
    if !excludes.is_empty() {
        let drop: Vec<SegmentName> = excludes
            .iter()
            .filter_map(|s| SegmentName::parse(s))
            .collect();
        for line in &mut layout.lines {
            line.retain(|name| !drop.contains(name));
        }
        layout.lines.retain(|line| !line.is_empty());
    }
    if layout.lines.is_empty() {
        return Layout::two_line();
    }
    layout
}

fn resolve_base(cli_layout: Option<&str>, cli_config: Option<&Path>) -> Layout {
    if let Some(spec) = cli_layout
        && let Ok(l) = Layout::parse(spec)
    {
        return l;
    }

    // Explicit `--config` takes precedence over the XDG default. If the
    // user named a file we honor it even on read failure (we still fall
    // through to the built-in default rather than the XDG file - the
    // explicit path is a stronger signal of intent).
    if let Some(path) = cli_config {
        if let Ok(text) = std::fs::read_to_string(path) {
            let stripped = strip_comments(&text);
            if let Ok(l) = Layout::parse(&stripped) {
                return l;
            }
        }
        return Layout::two_line();
    }

    if let Some(path) = config_file()
        && let Ok(text) = std::fs::read_to_string(&path)
    {
        let stripped = strip_comments(&text);
        if let Ok(l) = Layout::parse(&stripped) {
            return l;
        }
    }

    Layout::two_line()
}

fn config_file() -> Option<PathBuf> {
    Some(dirs::config_dir()?.join("claude-statusline").join("layout"))
}

/// Strip `#`-style line comments. Naive on purpose: a `#` inside a
/// segment name would be a parse error anyway, so there's nothing to
/// quote-escape.
fn strip_comments(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for line in text.lines() {
        let cut = line.find('#').unwrap_or(line.len());
        out.push_str(&line[..cut]);
        out.push('\n');
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_trailing_comments() {
        let s = strip_comments("dir, vcs # the top line\ncost # bottom");
        assert!(!s.contains('#'));
        assert!(s.contains("dir, vcs"));
        assert!(s.contains("cost"));
    }

    #[test]
    fn cli_layout_overrides_default() {
        let l = load(Some("dir"), None, &[]);
        assert_eq!(l.lines.len(), 1);
        assert_eq!(l.lines[0].len(), 1);
    }

    #[test]
    fn invalid_cli_layout_falls_back_to_default() {
        let l = load(Some("definitely-not-a-segment"), None, &[]);
        assert_eq!(l.lines.len(), 2); // two-line default
    }

    #[test]
    fn excludes_strip_segments_from_resolved_layout() {
        let l = load(
            Some("dir,vcs,model | cost,diff,context,rate_limits"),
            None,
            &["cost".to_string(), "rates".to_string()],
        );
        assert_eq!(l.lines.len(), 2);
        assert_eq!(l.lines[1], vec![SegmentName::Diff, SegmentName::Context]);
    }

    #[test]
    fn excluding_everything_falls_back_to_default() {
        // If the user excludes every segment, we'd otherwise emit a
        // blank statusline - fall back to the built-in default instead.
        let l = load(Some("dir"), None, &["dir".to_string()]);
        assert_eq!(l.lines.len(), 2);
    }
}
