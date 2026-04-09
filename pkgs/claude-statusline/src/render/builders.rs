//! Per-segment builders. Each function returns an `Option<Segment>` of
//! styled cells; passing `None` upstream tells the layout to skip the
//! position cleanly.

use crate::input::{Input, RateLimit};
use crate::pricing::cost::format_usd;
use crate::render::colors::Palette;
use crate::render::format::{humanize_duration, humanize_tokens, shorten_model};
use crate::render::icons::Icons;
use crate::render::segment::Segment;
use crate::session::Deltas;
use crate::settings::{ContextFormat, DirStyle, Settings};

pub fn dir(input: &Input, settings: &Settings) -> Segment {
    let mut s = Segment::new(false);
    let text = match settings.dir_style {
        DirStyle::Basename => input.dir_name(),
        DirStyle::Full => input.dir_full(),
        DirStyle::Home => input.dir_home(),
    };
    if settings.hyperlinks {
        if let Some(full_path) = input.workspace.current_dir.as_deref() {
            let url = format!("file://{full_path}");
            s.push_linked(text, anstyle::Style::new(), url);
        } else {
            s.push_plain(text);
        }
    } else {
        s.push_plain(text);
    }
    s
}

pub fn model(input: &Input, _icons: &Icons, pal: &Palette) -> Option<Segment> {
    let name = input.model.display_name.as_deref()?;
    let short = shorten_model(name);
    if short.is_empty() {
        return None;
    }
    let mut s = Segment::new(true);
    s.push_styled(short, pal.blue);
    Some(s)
}

pub fn cost(
    input: &Input,
    cost_usd: Option<f64>,
    deltas: &Deltas,
    settings: &Settings,
    pal: &Palette,
) -> Option<Segment> {
    let cost = cost_usd?;
    if cost <= 0.0 {
        return None;
    }
    let mut s = Segment::new(true);
    s.push_styled(format_usd(cost), pal.green);
    if settings.flash && deltas.is_cost() {
        s.push_plain(" ");
        s.push_styled(format!("+{}", format_usd(deltas.cost_usd)), pal.bold_green);
    }
    if let Some(api_ms) = input.cost.total_api_duration_ms
        && api_ms > 0
    {
        #[allow(clippy::cast_possible_wrap)]
        let dur = humanize_duration((api_ms / 1000) as i64);
        if !dur.is_empty() {
            s.push_plain(" ");
            s.push_styled(format!("wait {dur}"), pal.dim);
        }
    }
    Some(s)
}

pub fn diff(input: &Input, deltas: &Deltas, settings: &Settings, pal: &Palette) -> Option<Segment> {
    let added = input.cost.total_lines_added.unwrap_or(0);
    let removed = input.cost.total_lines_removed.unwrap_or(0);
    if added == 0 && removed == 0 {
        return None;
    }
    let mut s = Segment::new(true);
    s.push_styled(format!("+{added}"), pal.green);
    if settings.flash && deltas.lines_added > 0 {
        s.push_styled(format!(" (+{})", deltas.lines_added), pal.bold_green);
    }
    s.push_plain(" ");
    s.push_styled(format!("-{removed}"), pal.red);
    if settings.flash && deltas.lines_removed > 0 {
        s.push_styled(format!(" (-{})", deltas.lines_removed), pal.bold_red);
    }
    Some(s)
}

pub fn context(
    input: &Input,
    deltas: &Deltas,
    settings: &Settings,
    pal: &Palette,
) -> Option<Segment> {
    let used = input.context_window.used_percentage?;
    let pct = used.round() as i64;
    if pct < 0 {
        return None;
    }
    let pct = pct as u32;
    let cur_tokens = input.context_window.current_usage.total();
    let max_tokens = input.context_window.context_window_size.unwrap_or(0);
    let have_tokens = cur_tokens > 0 && max_tokens > 0;
    let style = if have_tokens {
        pal.color_for_token_count(cur_tokens)
    } else {
        pal.color_for_pct(pct, 50, 75)
    };

    let text = if have_tokens && !matches!(settings.context_format, ContextFormat::Percent) {
        format!(
            "{}/{}",
            humanize_tokens(cur_tokens),
            humanize_tokens(max_tokens)
        )
    } else {
        format!("{pct}%")
    };
    let mut s = Segment::new(true);
    s.push_styled(text, style);
    if settings.flash && deltas.is_context() {
        s.push_styled(
            format!(" (+{})", humanize_tokens(deltas.context_tokens)),
            pal.bold_cyan,
        );
    }
    Some(s)
}

struct RateLimitRow<'a> {
    label: &'static str,
    slot: &'a RateLimit,
    visibility_floor: Option<u32>,
    show_countdown: bool,
}

struct VisibleRow<'a> {
    label: &'static str,
    pct: u32,
    slot: &'a RateLimit,
    show_countdown: bool,
}

impl<'a> RateLimitRow<'a> {
    fn resolve(&self) -> Option<VisibleRow<'a>> {
        let raw = self.slot.used_percentage?.round();
        if raw < 0.0 {
            return None;
        }
        let pct = raw as u32;
        if let Some(min) = self.visibility_floor
            && pct < min
        {
            return None;
        }
        Some(VisibleRow {
            label: self.label,
            pct,
            slot: self.slot,
            show_countdown: self.show_countdown,
        })
    }
}

pub fn rate_limits(
    input: &Input,
    icons: &Icons,
    settings: &Settings,
    pal: &Palette,
) -> Option<Segment> {
    use std::time::{SystemTime, UNIX_EPOCH};
    let now = SystemTime::now().duration_since(UNIX_EPOCH).ok().map(|d| {
        #[allow(clippy::cast_possible_wrap)]
        let secs = d.as_secs() as i64;
        secs
    });

    let rows = [
        RateLimitRow {
            label: "5h",
            slot: &input.rate_limits.five_hour,
            visibility_floor: None,
            show_countdown: true,
        },
        RateLimitRow {
            label: "7d",
            slot: &input.rate_limits.seven_day,
            visibility_floor: Some(settings.seven_day_threshold),
            show_countdown: false,
        },
    ];

    let visible: Vec<VisibleRow<'_>> = rows.iter().filter_map(RateLimitRow::resolve).collect();
    if visible.is_empty() {
        return None;
    }

    let mut s = Segment::new(true);
    if !icons.clock.is_empty() {
        s.push_plain(format!("{} ", icons.clock));
    }
    for (i, row) in visible.iter().enumerate() {
        if i > 0 {
            s.push_plain("  ");
        }
        s.push_styled(row.label, pal.dim);
        s.push_plain(" ");
        s.push_styled(format!("{}%", row.pct), pal.color_for_pct(row.pct, 50, 100));

        if row.show_countdown
            && let (Some(now), Some(reset)) = (now, row.slot.resets_at)
        {
            let remaining = reset - now;
            if remaining > 0 {
                s.push_plain(" ");
                s.push_styled(humanize_duration(remaining), pal.dim);
            }
        }
    }
    Some(s)
}
