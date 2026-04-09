//! Structured statusline AST.
//!
//! Each [`Segment`] is a list of styled [`Cell`]s. The renderer assembles
//! cells into final ANSI output and computes display widths from raw text
//! (no regex strip needed, because the text and the style live in
//! separate fields).
//!
//! Builders in [`crate::render::builders`] produce `Option<Segment>`s;
//! the renderer in [`crate::render`] consumes them. This is the only
//! place that knows about styled text - every other module manipulates
//! plain `&str` / `String` plus [`anstyle::Style`] values.

use anstyle::{Reset, Style};
use compact_str::CompactString;
use unicode_width::UnicodeWidthStr;

/// A run of text with a single style applied. Cells are the leaves of
/// the AST: they don't combine, they don't compose styles, they're just
/// "render this text in this color".
///
/// `text` is a [`CompactString`]: strings up to 24 bytes (which covers
/// nearly all statusline content — icons, short labels, `$0.42`, branch
/// names) are stored inline without a heap allocation.
///
/// An optional `link` wraps the cell in an OSC 8 hyperlink when the
/// terminal supports it.
#[derive(Debug, Clone)]
pub struct Cell {
    pub text: CompactString,
    pub style: Style,
    pub link: Option<CompactString>,
}

impl Cell {
    pub fn new(text: impl Into<CompactString>, style: Style) -> Self {
        Self {
            text: text.into(),
            style,
            link: None,
        }
    }

    pub fn plain(text: impl Into<CompactString>) -> Self {
        Self::new(text, Style::new())
    }

    pub fn linked(
        text: impl Into<CompactString>,
        style: Style,
        url: impl Into<CompactString>,
    ) -> Self {
        Self {
            text: text.into(),
            style,
            link: Some(url.into()),
        }
    }

    pub fn width(&self) -> usize {
        UnicodeWidthStr::width(self.text.as_str())
    }

    pub fn write_to(&self, out: &mut String) {
        let has_link = self.link.is_some();
        if let Some(url) = &self.link {
            // OSC 8 open: \x1b]8;;<url>\x1b\\
            use std::fmt::Write as _;
            let _ = write!(out, "\x1b]8;;{url}\x1b\\");
        }
        if self.style == Style::new() {
            out.push_str(&self.text);
        } else {
            use std::fmt::Write as _;
            let _ = write!(out, "{}{}{}", self.style, self.text, Reset);
        }
        if has_link {
            // OSC 8 close: \x1b]8;;\x1b\\
            out.push_str("\x1b]8;;\x1b\\");
        }
    }
}

/// A statusline chunk (one logical thing: dir, vcs info, cost, …). The
/// `droppable` flag tells the renderer it's safe to elide this segment
/// when the line wouldn't fit in the terminal width.
#[derive(Debug, Clone)]
pub struct Segment {
    pub cells: Vec<Cell>,
    pub droppable: bool,
}

impl Segment {
    pub const fn new(droppable: bool) -> Self {
        Self {
            cells: Vec::new(),
            droppable,
        }
    }

    pub fn push_plain(&mut self, text: impl Into<CompactString>) -> &mut Self {
        self.cells.push(Cell::plain(text));
        self
    }

    pub fn push_styled(&mut self, text: impl Into<CompactString>, style: Style) -> &mut Self {
        self.cells.push(Cell::new(text, style));
        self
    }

    pub fn push_linked(
        &mut self,
        text: impl Into<CompactString>,
        style: Style,
        url: impl Into<CompactString>,
    ) -> &mut Self {
        self.cells.push(Cell::linked(text, style, url));
        self
    }

    pub fn width(&self) -> usize {
        self.cells.iter().map(Cell::width).sum()
    }

    pub const fn is_empty(&self) -> bool {
        self.cells.is_empty()
    }

    pub fn write_to(&self, out: &mut String) {
        for cell in &self.cells {
            cell.write_to(out);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cell_width_counts_emoji_and_ascii() {
        assert_eq!(Cell::plain("hello").width(), 5);
        assert!(Cell::plain("🌿").width() >= 1);
    }

    #[test]
    fn plain_cell_emits_no_escapes() {
        let mut out = String::new();
        Cell::plain("foo").write_to(&mut out);
        assert_eq!(out, "foo");
    }

    #[test]
    fn styled_cell_wraps_in_sgr_and_reset() {
        let mut out = String::new();
        Cell::new("foo", anstyle::AnsiColor::Green.on_default()).write_to(&mut out);
        assert!(out.starts_with("\x1b["));
        assert!(out.contains("foo"));
        assert!(out.ends_with("\x1b[0m"));
    }

    #[test]
    fn segment_width_sums_cells() {
        let mut s = Segment::new(true);
        s.push_plain("ab");
        s.push_plain("cde");
        assert_eq!(s.width(), 5);
    }
}
