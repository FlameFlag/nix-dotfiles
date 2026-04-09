//! Multi-line statusline rendering driven by a [`Layout`].
//!
//! The renderer is now a thin string serializer: it asks each named
//! segment to build itself, then joins the resulting [`Segment`]s with a
//! visible separator and drops droppable segments from the right when
//! the line wouldn't fit in the terminal width. Every line is budgeted
//! independently - line 1 (identity) and line 2 (telemetry) wrap on
//! their own.

pub mod builders;
pub mod colors;
pub mod fit;
pub mod format;
pub mod icons;
pub mod layout;
pub mod preview;
pub mod segment;
mod write;

use crate::input::Input;
use crate::pricing::cost::session_cost;
use crate::render::colors::Palette;
use crate::render::icons::Icons;
use crate::render::layout::{BuildCtx, Layout, SegmentName};
use crate::render::segment::Segment;
use crate::session;
use crate::settings::Settings;
use crate::vcs;

/// Convenience: render with the historical defaults. Used by tests
/// (which don't care about settings) and benches.
pub fn render(input: &Input, icons: &Icons, layout: &Layout) -> String {
    render_with(input, icons, layout, &Settings::default(), &Palette::dark())
}

pub fn render_with(
    input: &Input,
    icons: &Icons,
    layout: &Layout,
    settings: &Settings,
    pal: &Palette,
) -> String {
    let want_vcs = layout.contains(SegmentName::Vcs);
    let want_cost = layout.contains(SegmentName::Cost);
    let needs_transcript_walk =
        want_cost && input.cost.total_cost_usd.is_none() && input.transcript_path.is_some();

    let (vcs_seg, cost_usd) = if want_vcs && needs_transcript_walk {
        std::thread::scope(|s| {
            let vcs_handle = s.spawn(|| vcs::collect(&input.vcs_dir(), icons, pal));
            let cost_handle = s.spawn(|| {
                session_cost(input.transcript_path.as_deref(), input.cost.total_cost_usd)
            });
            (
                vcs_handle.join().unwrap_or(None),
                cost_handle.join().unwrap_or(None),
            )
        })
    } else {
        let vcs_seg = if want_vcs {
            vcs::collect(&input.vcs_dir(), icons, pal)
        } else {
            None
        };
        let cost_usd = if want_cost {
            session_cost(input.transcript_path.as_deref(), input.cost.total_cost_usd)
        } else {
            None
        };
        (vcs_seg, cost_usd)
    };

    let deltas = session::update(
        session::session_key(input.transcript_path.as_deref()).as_deref(),
        cost_usd,
        input.cost.total_lines_added,
        input.cost.total_lines_removed,
        Some(input.context_window.current_usage.total()),
        if settings.flash {
            settings.flash_ttl_secs
        } else {
            0
        },
    );

    let ctx = BuildCtx {
        input,
        icons,
        palette: pal,
        vcs: vcs_seg,
        cost_usd,
        deltas,
        settings,
    };
    render_lines(&ctx, layout, None)
}

/// Build -> fit -> write pipeline given an already-prepared [`BuildCtx`].
pub(crate) fn render_lines(
    ctx: &BuildCtx<'_>,
    layout: &Layout,
    max_cols_override: Option<usize>,
) -> String {
    let settings = ctx.settings;
    let icons = ctx.icons;
    let pal = ctx.palette;
    let max_cols = max_cols_override.or_else(|| {
        terminal_size::terminal_size()
            .map(|(w, _)| w.0 as usize)
            .filter(|c| *c > 10)
    });
    let separator = write::build_separator(icons.sep, pal);

    let mut lines: Vec<Vec<Segment>> = layout
        .lines
        .iter()
        .map(|line| {
            line.iter()
                .filter_map(|name| name.build(ctx))
                .filter(|s| !s.is_empty())
                .collect()
        })
        .collect();

    if settings.align {
        fit_with_alignment(&mut lines, separator.width, max_cols);
    } else {
        fit_unaligned(&mut lines, separator.width, max_cols);
    }

    let col_widths: Vec<usize> = if settings.align {
        column_widths(&lines)
    } else {
        Vec::new()
    };

    let mut out = String::new();
    for (i, segments) in lines.iter().enumerate() {
        if i > 0 {
            out.push('\n');
        }
        write::write_line(&mut out, segments, &separator, &col_widths);
    }
    out
}

pub use fit::{aligned_width, column_widths, fit_unaligned, fit_with_alignment};

#[cfg(test)]
mod tests {
    use super::*;
    use crate::input::{Cost, Input, RateLimit, RateLimits};
    use crate::render::icons::IconSet;
    use crate::render::layout::Layout;

    fn icons() -> &'static Icons {
        IconSet::Text.icons()
    }

    fn pal() -> Palette {
        Palette::dark()
    }

    #[test]
    fn two_line_default_renders_two_lines() {
        let input = Input {
            workspace: crate::input::Workspace {
                current_dir: Some("/tmp/foo".into()),
            },
            cost: Cost {
                total_cost_usd: Some(0.42),
                ..Default::default()
            },
            ..Default::default()
        };
        let layout = Layout::two_line();
        let out = render(&input, icons(), &layout);
        assert_eq!(out.lines().count(), 2, "got: {out:?}");
    }

    #[test]
    fn single_line_layout_renders_one_line() {
        let input = Input::default();
        let layout = Layout::parse("dir").unwrap();
        let out = render(&input, icons(), &layout);
        assert_eq!(out.lines().count(), 1);
        assert!(!out.contains('\n'));
    }

    fn strip_ansi(s: &str) -> String {
        let mut out = String::with_capacity(s.len());
        let mut chars = s.chars();
        while let Some(c) = chars.next() {
            if c == '\x1b' {
                for nc in chars.by_ref() {
                    if nc == 'm' {
                        break;
                    }
                }
                continue;
            }
            out.push(c);
        }
        out
    }

    #[test]
    fn columns_align_across_lines() {
        use crate::render::segment::Segment;
        let p = pal();
        let mut a1 = Segment::new(false);
        a1.push_plain("claude-statusline");
        let mut a2 = Segment::new(false);
        a2.push_plain("Opus");
        let mut b1 = Segment::new(false);
        b1.push_plain("$0.22");
        let mut b2 = Segment::new(false);
        b2.push_plain("5h 7%");
        let lines = vec![vec![a1, a2], vec![b1, b2]];
        let sep = write::build_separator("│", &p);
        let widths = column_widths(&lines);
        let mut out = String::new();
        for (i, line) in lines.iter().enumerate() {
            if i > 0 {
                out.push('\n');
            }
            write::write_line(&mut out, line, &sep, &widths);
        }
        let plain = strip_ansi(&out);
        let mut sep_cols: Vec<usize> = Vec::new();
        for line in plain.lines() {
            sep_cols.push(line.find('│').expect("separator missing"));
        }
        assert_eq!(sep_cols[0], sep_cols[1], "separators misaligned: {plain:?}");
    }

    #[test]
    fn last_segment_is_not_padded() {
        use crate::render::segment::Segment;
        let p = pal();
        let mut a1 = Segment::new(false);
        a1.push_plain("aaaa");
        let mut a2 = Segment::new(false);
        a2.push_plain("b");
        let mut c1 = Segment::new(false);
        c1.push_plain("a");
        let mut c2 = Segment::new(false);
        c2.push_plain("bbbbbb");
        let lines = vec![vec![a1, a2], vec![c1, c2]];
        let sep = write::build_separator("│", &p);
        let widths = column_widths(&lines);
        let mut out = String::new();
        for (i, line) in lines.iter().enumerate() {
            if i > 0 {
                out.push('\n');
            }
            write::write_line(&mut out, line, &sep, &widths);
        }
        let plain = strip_ansi(&out);
        for line in plain.lines() {
            assert_eq!(line, line.trim_end(), "trailing whitespace in {line:?}");
        }
    }

    #[test]
    fn missing_segments_are_skipped_not_blank() {
        let input = Input::default();
        let layout = Layout::two_line();
        let out = render(&input, icons(), &layout);
        assert!(out.lines().next().is_some());
    }

    #[test]
    fn rate_limits_segment_includes_countdown() {
        use std::time::{SystemTime, UNIX_EPOCH};
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_secs() as i64;
        let input = Input {
            rate_limits: RateLimits {
                five_hour: RateLimit {
                    used_percentage: Some(72.0),
                    resets_at: Some(now + 5000),
                },
                seven_day: RateLimit::default(),
            },
            ..Default::default()
        };
        let layout = Layout::parse("rate_limits").unwrap();
        let out = render(&input, icons(), &layout);
        assert!(out.contains("72%"), "got: {out}");
        assert!(out.contains("1h 23m"), "got: {out}");
    }

    #[test]
    fn cost_segment_appends_model_duration() {
        let input = Input {
            cost: Cost {
                total_cost_usd: Some(0.42),
                total_api_duration_ms: Some(750_000),
                ..Default::default()
            },
            ..Default::default()
        };
        let layout = Layout::parse("cost").unwrap();
        let out = render(&input, icons(), &layout);
        assert!(out.contains("$0.42"), "got: {out}");
        assert!(out.contains("wait 12m"), "got: {out}");
    }

    #[test]
    fn diff_segment_renders_added_and_removed() {
        let input = Input {
            cost: Cost {
                total_lines_added: Some(342),
                total_lines_removed: Some(89),
                ..Default::default()
            },
            ..Default::default()
        };
        let layout = Layout::parse("diff").unwrap();
        let out = render(&input, icons(), &layout);
        assert!(out.contains("+342"));
        assert!(out.contains("-89"));
    }
}
