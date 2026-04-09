//! Command-line interface definition.
//!
//! Help is deliberately terse: every flag's `help` is a single line, and
//! `long_help` is only set where the extra prose actually changes how
//! the user would invoke the flag. The global `long_about` carries the
//! segment cheatsheet so `--help` reads like a reference card instead
//! of a manpage.

use std::path::PathBuf;

use clap::{Parser, ValueEnum};

use crate::render::icons::IconSet;
use crate::settings::{ContextFormat, DirStyle, Settings};
use crate::theme::ThemeMode;

const LONG_ABOUT: &str = "\
Fast Claude Code statusline (gix + jj-lib).

Segments:
  dir          working directory basename (anchor)
  vcs          git/jj branch + status            (alias: git, jj)
  model        Claude model display name
  cost         session $ + cumulative model time
  diff         lines added / removed             (alias: lines)
  context      context-window usage              (alias: ctx)
  rate_limits  5h / 7d quota                     (alias: rates)

Layout DSL:
  Comma `,` separates segments inside a line.
  Pipe  `|` (or a real newline in a config file) separates lines.
  The first segment of each line is its anchor and is never dropped.
  Pass `--preview` with any layout to see it rendered against sample data.";

/// Layout shapes embedded in `--help`.
///
/// Each entry is a `(label, dsl)` pair; `main` walks this list, runs
/// `preview_with` against each shape, and folds the rendered output
/// into the `after_help` block at runtime. Keeping the table here
/// (rather than inline in `main`) means the cli module owns the
/// user-facing strings end-to-end.
pub const HELP_LAYOUT_SHAPES: &[(&str, &str)] = &[
    ("one line", "dir,vcs,rates,context,cost,model"),
    (
        "two line (default)",
        "dir,vcs,rates,context | cost,diff,model",
    ),
    ("three line", "dir,vcs | rates,context | cost,diff,model"),
    ("stacked", "dir | vcs | cost | context"),
];

/// Trailer appended after the rendered shape examples in `--help`.
/// Kept as a const so it stays grep-able and we don't bury copy in
/// `main.rs`.
pub const HELP_AFTER_EXAMPLES: &str = "\
Other examples:
  claude-statusline --exclude cost,rates < payload.json
  claude-statusline --separator ' • ' --no-align
  claude-statusline --dir home --context-format percent
  claude-statusline --preview --layout 'dir,vcs,model | cost,context'
  claude-statusline --completions zsh > _claude-statusline

Config file (same DSL, `#` comments allowed):
  $XDG_CONFIG_HOME/claude-statusline/layout";

#[derive(Parser, Debug)]
#[command(
    version,
    about = "Fast Claude Code statusline (gix + jj-lib)",
    long_about = LONG_ABOUT,
    // `after_help` is set at runtime by `main` to include rendered
    // preview output (requires runtime icon detection).
    max_term_width = 100,
)]
pub struct Cli {
    /// Layout DSL: `dir,vcs,model | cost,context,rates`
    #[arg(
        short = 'l',
        long,
        env = "CLAUDE_STATUSLINE_LAYOUT",
        value_name = "DSL",
        help_heading = "Layout",
        hide_env = true
    )]
    pub layout: Option<String>,

    /// Drop named segments from the resolved layout
    #[arg(
        short = 'x',
        long,
        env = "CLAUDE_STATUSLINE_EXCLUDE",
        value_delimiter = ',',
        value_name = "NAMES",
        help_heading = "Layout",
        hide_env = true
    )]
    pub exclude: Vec<String>,

    /// Layout config file (defaults to
    /// $XDG_CONFIG_HOME/claude-statusline/layout)
    #[arg(
        short = 'c',
        long,
        env = "CLAUDE_STATUSLINE_CONFIG",
        value_name = "PATH",
        help_heading = "Layout",
        hide_env = true
    )]
    pub config: Option<PathBuf>,

    /// Disable cross-line column alignment (compact, ragged-right output)
    #[arg(
        long = "no-align",
        env = "CLAUDE_STATUSLINE_NO_ALIGN",
        help_heading = "Layout",
        hide_env = true,
        action = clap::ArgAction::SetTrue,
    )]
    pub no_align: bool,

    /// When to emit ANSI color escapes
    #[arg(
        long,
        value_enum,
        default_value_t = ColorChoice::Always,
        env = "CLAUDE_STATUSLINE_COLOR",
        help_heading = "Display",
        hide_env = true,
    )]
    pub color: ColorChoice,

    /// Icon set [auto-detected from terminal font when unset]
    #[arg(
        short = 'i',
        long,
        value_enum,
        env = "CLAUDE_STATUSLINE_ICONS",
        value_name = "SET",
        help_heading = "Display",
        hide_env = true
    )]
    pub icons: Option<IconSet>,

    /// Override the column separator glyph (default: ` │ `)
    #[arg(
        short = 's',
        long,
        env = "CLAUDE_STATUSLINE_SEPARATOR",
        value_name = "STR",
        help_heading = "Display",
        hide_env = true
    )]
    pub separator: Option<String>,

    /// How the dir segment renders the cwd
    #[arg(
        long,
        value_enum,
        env = "CLAUDE_STATUSLINE_DIR",
        value_name = "STYLE",
        default_value_t = DirStyle::default(),
        help_heading = "Display",
        hide_env = true,
        hide_default_value = true,
    )]
    pub dir: DirStyle,

    /// How the context segment formats usage
    #[arg(
        long = "context-format",
        value_enum,
        env = "CLAUDE_STATUSLINE_CONTEXT_FORMAT",
        value_name = "FMT",
        default_value_t = ContextFormat::default(),
        help_heading = "Display",
        hide_env = true,
        hide_default_value = true,
    )]
    pub context_format: ContextFormat,

    /// Visibility floor for the 7-day rate-limit row, in percent
    #[arg(
        long = "seven-day-threshold",
        env = "CLAUDE_STATUSLINE_SEVEN_DAY_THRESHOLD",
        value_name = "PCT",
        default_value_t = 80,
        help_heading = "Display",
        hide_env = true,
        hide_default_value = true
    )]
    pub seven_day_threshold: u32,

    /// Disable the delta highlight on cost / diff / context
    #[arg(
        long = "no-flash",
        env = "CLAUDE_STATUSLINE_NO_FLASH",
        help_heading = "Flash",
        hide_env = true,
        action = clap::ArgAction::SetTrue,
    )]
    pub no_flash: bool,

    /// How long a delta keeps flashing across renders, in seconds
    #[arg(
        long = "flash-ttl",
        env = "CLAUDE_STATUSLINE_FLASH_TTL",
        value_name = "SECS",
        default_value_t = 30,
        help_heading = "Flash",
        hide_env = true,
        hide_default_value = true
    )]
    pub flash_ttl: u64,

    /// Print shell completions to stdout and exit
    #[arg(
        long,
        value_enum,
        value_name = "SHELL",
        help_heading = "Shell integration"
    )]
    pub completions: Option<Shell>,

    /// Wrap the dir segment in an OSC 8 hyperlink (clickable in
    /// supported terminals). Auto-detected by default.
    #[arg(
        long,
        env = "CLAUDE_STATUSLINE_HYPERLINKS",
        help_heading = "Display",
        hide_env = true,
        action = clap::ArgAction::SetTrue,
    )]
    pub hyperlinks: bool,

    /// Terminal theme for color adaptation [auto-detected when unset]
    #[arg(
        long,
        value_enum,
        env = "CLAUDE_STATUSLINE_THEME",
        value_name = "MODE",
        default_value_t = ThemeMode::default(),
        help_heading = "Display",
        hide_env = true,
        hide_default_value = true,
    )]
    pub theme: ThemeMode,

    /// Render the resolved layout against sample data and exit
    #[arg(
        long,
        help_heading = "Shell integration",
        action = clap::ArgAction::SetTrue,
    )]
    pub preview: bool,
}

impl Cli {
    /// Collapse the parsed flags into the resolved [`Settings`] bundle
    /// the renderer consumes. Keeping this conversion here means
    /// `render()` never has to know about clap.
    pub fn to_settings(&self) -> Settings {
        // Auto-detect hyperlink support when the user hasn't explicitly
        // opted in via `--hyperlinks` or the env var.
        let hyperlinks = self.hyperlinks || supports_hyperlinks::supports_hyperlinks();
        Settings {
            flash: !self.no_flash,
            flash_ttl_secs: self.flash_ttl,
            align: !self.no_align,
            dir_style: self.dir,
            context_format: self.context_format,
            seven_day_threshold: self.seven_day_threshold,
            hyperlinks,
        }
    }
}

#[derive(Copy, Clone, Debug, ValueEnum)]
#[value(rename_all = "lower")]
pub enum ColorChoice {
    Auto,
    Always,
    Never,
}

impl From<ColorChoice> for anstream::ColorChoice {
    fn from(c: ColorChoice) -> Self {
        match c {
            ColorChoice::Auto => Self::Auto,
            ColorChoice::Always => Self::Always,
            ColorChoice::Never => Self::Never,
        }
    }
}

/// Target shell for `--completions`. Mirrors `clap_complete::Shell` but
/// adds Nushell (which lives in a separate crate) so we can expose all
/// the shells the user actually cares about behind one enum.
#[derive(Copy, Clone, Debug, ValueEnum)]
#[value(rename_all = "lower")]
pub enum Shell {
    Bash,
    Zsh,
    Fish,
    Nushell,
    Elvish,
    PowerShell,
}
