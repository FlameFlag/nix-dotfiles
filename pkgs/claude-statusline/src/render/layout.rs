//! User-configurable layout: which segments appear, on which line, in
//! which order. The layout is a `Vec<Vec<SegmentName>>` (lines of named
//! segments), parsed from a tiny DSL or loaded from a config file.
//!
//! DSL syntax:
//!
//! ```text
//! dir,vcs,model | cost,diff,context,rate_limits
//! ```
//!
//! - `|` separates lines (use `\n` in config files for readability).
//! - `,` separates segments inside a line.
//! - Whitespace is ignored.
//! - Unknown segment names are an error so typos surface immediately.
//!
//! The first segment of each line is the line's *anchor*: it is never
//! dropped, even when the terminal is too narrow. Every other segment
//! is droppable from the right.

use std::fmt;

use crate::input::Input;
use crate::render::builders;
use crate::render::colors::Palette;
use crate::render::segment::Segment;
use crate::session::Deltas;
use crate::settings::Settings;

/// Names of every renderable segment. Add a variant here, wire it in
/// [`SegmentName::build`] and [`SegmentName::parse`], and it instantly
/// becomes available in the layout DSL.
#[derive(Copy, Clone, Debug, Eq, PartialEq, Hash)]
pub enum SegmentName {
    Dir,
    Vcs,
    Model,
    Cost,
    Diff,
    Context,
    RateLimits,
}

impl SegmentName {
    /// Canonical name used by the DSL parser. The inverse of [`parse`]:
    /// `parse(canonical(x)) == Some(x)` for every variant. Used by the
    /// `--preview` header so the user can see exactly which form their
    /// resolved layout is in.
    pub const fn canonical(self) -> &'static str {
        match self {
            Self::Dir => "dir",
            Self::Vcs => "vcs",
            Self::Model => "model",
            Self::Cost => "cost",
            Self::Diff => "diff",
            Self::Context => "context",
            Self::RateLimits => "rate_limits",
        }
    }

    pub fn parse(s: &str) -> Option<Self> {
        Some(match s.trim() {
            "dir" => Self::Dir,
            "vcs" | "git" | "jj" => Self::Vcs,
            "model" => Self::Model,
            "cost" => Self::Cost,
            "diff" | "lines" => Self::Diff,
            "context" | "ctx" => Self::Context,
            "rate_limits" | "rate-limits" | "rates" | "limits" => Self::RateLimits,
            _ => return None,
        })
    }

    /// Build the styled [`Segment`] for this name. Returns `None` when
    /// the underlying data is missing - the renderer drops the line
    /// position cleanly.
    pub fn build(self, ctx: &BuildCtx<'_>) -> Option<Segment> {
        let pal = ctx.palette;
        match self {
            Self::Dir => Some(builders::dir(ctx.input, ctx.settings)),
            Self::Vcs => ctx.vcs.clone(),
            Self::Model => builders::model(ctx.input, ctx.icons, pal),
            Self::Cost => builders::cost(ctx.input, ctx.cost_usd, &ctx.deltas, ctx.settings, pal),
            Self::Diff => builders::diff(ctx.input, &ctx.deltas, ctx.settings, pal),
            Self::Context => builders::context(ctx.input, &ctx.deltas, ctx.settings, pal),
            Self::RateLimits => builders::rate_limits(ctx.input, ctx.icons, ctx.settings, pal),
        }
    }
}

/// Bundle passed to every segment builder. `vcs` and `cost_usd` are
/// precomputed in a scoped thread; `deltas` carries flash state.
#[derive(Debug)]
pub struct BuildCtx<'a> {
    pub input: &'a Input,
    pub icons: &'a crate::render::icons::Icons,
    pub palette: &'a Palette,
    pub vcs: Option<Segment>,
    pub cost_usd: Option<f64>,
    pub deltas: Deltas,
    pub settings: &'a Settings,
}

#[derive(Debug, Clone)]
pub struct Layout {
    pub lines: Vec<Vec<SegmentName>>,
}

impl fmt::Display for Layout {
    /// Render the layout back into DSL form. Lines are joined with
    /// ` | ` and segments inside a line with `,`. Round-trips through
    /// [`Layout::parse`].
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        for (i, line) in self.lines.iter().enumerate() {
            if i > 0 {
                f.write_str(" | ")?;
            }
            for (j, name) in line.iter().enumerate() {
                if j > 0 {
                    f.write_str(",")?;
                }
                f.write_str(name.canonical())?;
            }
        }
        Ok(())
    }
}

impl Layout {
    /// Does this layout reference the given segment anywhere? Used by
    /// `render()` to skip precomputing data for segments that won't be
    /// displayed (e.g. don't walk the transcript if `Cost` isn't in the
    /// layout, don't open a git repo if `Vcs` isn't in the layout).
    pub fn contains(&self, name: SegmentName) -> bool {
        self.lines.iter().any(|line| line.contains(&name))
    }

    /// Default layout. The actionable info - context and rate limits —
    /// rides on the top line where it's hardest to miss; the cumulative
    /// figures (cost, diff) and the model name sit below. Earlier
    /// versions kept the model name on top, which buried the rate-limit
    /// countdown that users actually need to see at a glance.
    pub fn two_line() -> Self {
        use SegmentName::{Context, Cost, Diff, Dir, Model, RateLimits, Vcs};
        Self {
            lines: vec![vec![Dir, Context, RateLimits, Vcs], vec![Model, Diff, Cost]],
        }
    }

    /// Parse the DSL described in this module's docstring. Returns
    /// [`ParseError`] on unknown names or empty input so misconfigured
    /// users get a clear failure rather than a silently-empty prompt.
    pub fn parse(spec: &str) -> Result<Self, ParseError> {
        let mut lines: Vec<Vec<SegmentName>> = Vec::new();
        // Accept both `|` (one-line DSL) and literal newlines (config
        // file form) as line separators - they're never valid inside a
        // segment name so the split is unambiguous.
        for raw_line in spec.split(['|', '\n']) {
            let trimmed = raw_line.trim();
            if trimmed.is_empty() {
                continue;
            }
            let mut line = Vec::new();
            for tok in trimmed.split(',') {
                let tok = tok.trim();
                if tok.is_empty() {
                    continue;
                }
                let name =
                    SegmentName::parse(tok).ok_or_else(|| ParseError::Unknown(tok.to_string()))?;
                line.push(name);
            }
            if !line.is_empty() {
                lines.push(line);
            }
        }
        if lines.is_empty() {
            return Err(ParseError::Empty);
        }
        Ok(Self { lines })
    }
}

#[derive(Debug)]
pub enum ParseError {
    Unknown(String),
    Empty,
}

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Unknown(name) => write!(f, "unknown segment `{name}`"),
            Self::Empty => write!(f, "layout is empty"),
        }
    }
}

impl std::error::Error for ParseError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_two_line_dsl() {
        let layout = Layout::parse("dir,vcs,model | cost,diff,context,rate_limits").unwrap();
        assert_eq!(layout.lines.len(), 2);
        assert_eq!(
            layout.lines[0],
            vec![SegmentName::Dir, SegmentName::Vcs, SegmentName::Model]
        );
        assert_eq!(
            layout.lines[1],
            vec![
                SegmentName::Cost,
                SegmentName::Diff,
                SegmentName::Context,
                SegmentName::RateLimits,
            ]
        );
    }

    #[test]
    fn parses_newline_separated_form() {
        let spec = "dir, vcs\ncost, context\n";
        let layout = Layout::parse(spec).unwrap();
        assert_eq!(layout.lines.len(), 2);
    }

    #[test]
    fn aliases_resolve_to_canonical_name() {
        let layout = Layout::parse("git, ctx, rates").unwrap();
        assert_eq!(
            layout.lines[0],
            vec![
                SegmentName::Vcs,
                SegmentName::Context,
                SegmentName::RateLimits
            ]
        );
    }

    #[test]
    fn unknown_segment_errors() {
        let err = Layout::parse("dir, foo").unwrap_err();
        match err {
            ParseError::Unknown(name) => assert_eq!(name, "foo"),
            _ => panic!("expected Unknown"),
        }
    }

    #[test]
    fn empty_layout_errors() {
        assert!(matches!(Layout::parse("   "), Err(ParseError::Empty)));
        assert!(matches!(Layout::parse("|"), Err(ParseError::Empty)));
    }

    #[test]
    fn default_two_line_has_two_lines() {
        let l = Layout::two_line();
        assert_eq!(l.lines.len(), 2);
        assert_eq!(l.lines[0][0], SegmentName::Dir);
    }
}
