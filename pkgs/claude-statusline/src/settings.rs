//! Resolved per-render settings.
//!
//! Flows from `Cli` -> `render()` -> `BuildCtx` -> builders. Defaults
//! produce the same output as omitting all customization flags.

use clap::ValueEnum;

/// How the `dir` segment renders the working directory.
#[derive(Copy, Clone, Debug, ValueEnum, Default, Eq, PartialEq)]
#[value(rename_all = "lower")]
pub enum DirStyle {
    /// Just the last path component (default).
    #[default]
    Basename,
    /// Full absolute path as Claude Code reported it.
    Full,
    /// Full path with `$HOME` collapsed to `~`.
    Home,
}

/// How the `context` segment formats the current usage figure.
#[derive(Copy, Clone, Debug, ValueEnum, Default, Eq, PartialEq)]
#[value(rename_all = "lower")]
pub enum ContextFormat {
    /// `162k/1.0M` when both numbers are known, otherwise `15%` (default).
    #[default]
    Auto,
    /// Always render the percentage (`15%`).
    Percent,
    /// Always render the token counts (`162k/1.0M`).
    Tokens,
}

/// Resolved values handed to every builder. Cheap to copy.
#[derive(Copy, Clone, Debug)]
pub struct Settings {
    /// Render delta highlights for cost/diff/context. False kills the
    /// `(+$0.08)` / `(+25k)` flashes entirely.
    pub flash: bool,
    /// How long a recorded delta keeps flashing across renders, in
    /// wall-clock seconds.
    pub flash_ttl_secs: u64,
    /// Pad each line's columns so separators line up across lines. False
    /// produces compact, ragged-right output (smaller for narrow terminals).
    pub align: bool,
    /// Working directory rendering style.
    pub dir_style: DirStyle,
    /// Context segment formatting.
    pub context_format: ContextFormat,
    /// Visibility floor for the 7-day rate-limit row, as a whole percent.
    pub seven_day_threshold: u32,
    /// Wrap the dir segment text in an OSC 8 hyperlink so it's clickable
    /// in supported terminals.
    pub hyperlinks: bool,
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            flash: true,
            flash_ttl_secs: 30,
            align: true,
            dir_style: DirStyle::Basename,
            context_format: ContextFormat::Auto,
            seven_day_threshold: 80,
            hyperlinks: false,
        }
    }
}
