//! Icon sets for the statusline.
//!
//! Three flavors are available: `nerd` (Nerd Font private use area glyphs),
//! `emoji` (broadly supported color emoji), and `text` (ASCII / BMP fallbacks
//! that work in any terminal). Selection happens via `--icons` or the
//! `CLAUDE_STATUSLINE_ICONS` env var.
//!
//! Default is `text` because Claude Code's embedded terminal does not always
//! resolve a Nerd Font, so PUA codepoints render as `􀄦`-style placeholders.

use clap::ValueEnum;
use nerd_font_symbols::{
    dev::{DEV_GIT_COMPARE, DEV_GIT_MERGE},
    fa::{
        FA_ARROW_DOWN, FA_ARROW_ROTATE_LEFT, FA_ARROW_UP, FA_BOLT, FA_CHECK, FA_CLOCK,
        FA_CODE_BRANCH, FA_INBOX, FA_MAGNIFYING_GLASS, FA_PLUS, FA_QUESTION,
        FA_TRIANGLE_EXCLAMATION,
    },
    oct::OCT_PLUS,
    ple::PL_BRANCH,
};

#[derive(Copy, Clone, Debug, ValueEnum, Default)]
#[value(rename_all = "lower")]
pub enum IconSet {
    /// Nerd Font glyphs (requires a patched font)
    Nerd,
    /// Color emoji
    Emoji,
    /// ASCII / BMP fallback (default)
    #[default]
    Text,
}

#[derive(Debug, Clone)]
pub struct Icons {
    pub sep: &'static str,
    /// Prefix glyph for the git VCS segment.
    pub git: &'static str,
    /// Prefix glyph for the jj VCS segment. Distinct from `git` so the
    /// two backends are visually distinguishable at a glance.
    pub jj: &'static str,
    pub ahead: &'static str,
    pub behind: &'static str,
    pub staged: &'static str,
    pub dirty: &'static str,
    pub clean: &'static str,
    pub untracked: &'static str,
    pub stash: &'static str,
    pub merge: &'static str,
    pub rebase: &'static str,
    pub cherry_pick: &'static str,
    pub revert: &'static str,
    pub bisect: &'static str,
    pub conflict: &'static str,
    pub clock: &'static str,
}

pub const NERD: Icons = Icons {
    sep: "│",
    git: PL_BRANCH,
    jj: FA_CODE_BRANCH,
    ahead: FA_ARROW_UP,
    behind: FA_ARROW_DOWN,
    staged: FA_PLUS,
    dirty: OCT_PLUS,
    clean: FA_CHECK,
    untracked: FA_QUESTION,
    stash: FA_INBOX,
    merge: DEV_GIT_MERGE,
    rebase: DEV_GIT_COMPARE,
    cherry_pick: FA_BOLT,
    revert: FA_ARROW_ROTATE_LEFT,
    bisect: FA_MAGNIFYING_GLASS,
    conflict: FA_TRIANGLE_EXCLAMATION,
    clock: FA_CLOCK,
};

pub const EMOJI: Icons = Icons {
    sep: "│",
    git: "🌿",
    jj: "🌱",
    ahead: "⬆",
    behind: "⬇",
    staged: "➕",
    dirty: "📝",
    clean: "✅",
    untracked: "❓",
    stash: "📦",
    merge: "🔀",
    rebase: "🔁",
    cherry_pick: "🍒",
    revert: "↩",
    bisect: "🔍",
    conflict: "⚠",
    clock: "⏱",
};

pub const TEXT: Icons = Icons {
    sep: "│",
    // Tiny letter-prefixes so jj and git are distinguishable in plain
    // text mode without leaning on color alone.
    git: "git",
    jj: "jj",
    ahead: "↑",
    behind: "↓",
    staged: "+",
    dirty: "●",
    clean: "●",
    untracked: "?",
    stash: "⊟",
    merge: "✘",
    rebase: "↻",
    cherry_pick: "⊕",
    revert: "↩",
    bisect: "⟐",
    conflict: "✘",
    clock: "⏱",
};

impl IconSet {
    pub const fn icons(self) -> &'static Icons {
        match self {
            Self::Nerd => &NERD,
            Self::Emoji => &EMOJI,
            Self::Text => &TEXT,
        }
    }
}
