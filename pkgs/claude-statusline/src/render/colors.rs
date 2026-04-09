//! Theme-aware color palette built on [`anstyle::Style`].
//!
//! Colors are grouped into a [`Palette`] that varies between dark and
//! light terminal backgrounds. Every segment builder and VCS collector
//! receives a `&Palette` from the render context and uses its fields
//! instead of bare color constants.

use anstyle::{AnsiColor, Effects, Style};

use crate::theme::ThemeMode;

/// All the styles the renderer uses, pre-computed for the active theme.
///
/// Every field is `Copy` (because `anstyle::Style` is `Copy`), so the
/// struct itself is `Copy` too – cheap to thread through the pipeline.
#[derive(Copy, Clone, Debug)]
pub struct Palette {
    pub dim: Style,
    pub cyan: Style,
    pub yellow: Style,
    pub red: Style,
    pub green: Style,
    pub magenta: Style,
    pub blue: Style,
    pub bold_green: Style,
    pub bold_red: Style,
    pub bold_cyan: Style,
}

const BOLD: Effects = Effects::BOLD;
const DIMMED: Effects = Effects::DIMMED;

impl Palette {
    /// Build the palette for a resolved theme mode. `Auto` is treated as
    /// dark — callers should resolve `Auto` to a concrete mode via
    /// [`crate::theme::detect`] before reaching here.
    pub const fn for_theme(mode: ThemeMode) -> Self {
        match mode {
            ThemeMode::Light => Self::light(),
            ThemeMode::Dark | ThemeMode::Auto => Self::dark(),
        }
    }

    /// Dark-background palette: the original color set that has shipped
    /// since day one.
    pub const fn dark() -> Self {
        Self {
            dim: AnsiColor::BrightBlack.on_default(),
            cyan: AnsiColor::Cyan.on_default(),
            yellow: AnsiColor::Yellow.on_default(),
            red: AnsiColor::Red.on_default(),
            green: AnsiColor::Green.on_default(),
            magenta: AnsiColor::Magenta.on_default(),
            blue: AnsiColor::Blue.on_default(),
            bold_green: AnsiColor::BrightGreen.on_default().effects(BOLD),
            bold_red: AnsiColor::BrightRed.on_default().effects(BOLD),
            bold_cyan: AnsiColor::BrightCyan.on_default().effects(BOLD),
        }
    }

    /// Light-background palette: adjusted for readability on white/cream
    /// backgrounds.
    ///
    /// Key changes from dark:
    /// - `dim` uses the DIMMED effect on the default foreground instead of
    ///   `BrightBlack`, which can be invisible on some light themes.
    /// - `cyan` swaps to Blue — Cyan is the most universally problematic ANSI
    ///   color on light backgrounds.
    /// - Flash highlights (bold_*) use the base ANSI color + Bold instead of the
    ///   Bright variant, which washes out on white.
    pub const fn light() -> Self {
        Self {
            dim: Style::new().effects(DIMMED),
            cyan: AnsiColor::Blue.on_default(),
            yellow: AnsiColor::Yellow.on_default(),
            red: AnsiColor::Red.on_default(),
            green: AnsiColor::Green.on_default(),
            magenta: AnsiColor::Magenta.on_default(),
            blue: AnsiColor::Blue.on_default(),
            bold_green: AnsiColor::Green.on_default().effects(BOLD),
            bold_red: AnsiColor::Red.on_default().effects(BOLD),
            bold_cyan: AnsiColor::Blue.on_default().effects(BOLD),
        }
    }

    /// Returns the style for a percentage value — low/mid/high urgency.
    pub const fn color_for_pct(&self, pct: u32, low: u32, high: u32) -> Style {
        if pct < low {
            self.cyan
        } else if pct < high {
            self.yellow
        } else {
            self.red
        }
    }

    /// Color the context segment by absolute token count, not percentage.
    /// 200k is where Anthropic's tiered pricing kicks in (input tokens get
    /// noticeably more expensive), so we surface yellow there even on a 1M
    /// window where the percentage looks comfortable. 300k is the "you are
    /// running hot" marker.
    pub const fn color_for_token_count(&self, tokens: u64) -> Style {
        if tokens >= 300_000 {
            self.red
        } else if tokens >= 200_000 {
            self.yellow
        } else {
            self.cyan
        }
    }
}
