//! Drop-to-fit algorithms for multi-line segment layouts.
//!
//! Given a set of lines (each a `Vec<Segment>`), these functions remove
//! droppable segments from the right until every line fits within the
//! terminal width. Two strategies are provided:
//!
//! - [`fit_with_alignment`]: accounts for cross-line column padding so that a
//!   wide segment in line A doesn't silently overflow line B.
//! - [`fit_unaligned`]: budgets each line independently on its raw width, used by
//!   `--no-align`.

use crate::render::segment::Segment;

/// Drop segments across all lines until every line fits in `max_cols`.
///
/// Accounts for the padding alignment will add. Each iteration finds
/// the worst-overflowing line, drops one droppable segment from its
/// right, then recomputes column widths - that lets a drop in line A
/// shrink a column and rescue line B too. Anchor segments (the first
/// of each line) are never dropped; if the worst line has nothing left
/// to drop we bail to avoid an infinite loop.
pub fn fit_with_alignment(lines: &mut [Vec<Segment>], sep_width: usize, max_cols: Option<usize>) {
    let Some(max) = max_cols else {
        return;
    };
    loop {
        let widths = column_widths(lines);
        let worst = lines
            .iter()
            .enumerate()
            .map(|(i, line)| (i, aligned_width(line, &widths, sep_width)))
            .filter(|(_, w)| *w > max)
            .max_by_key(|(_, w)| *w);
        let Some((i, _)) = worst else {
            return;
        };
        let drop_idx = lines[i]
            .iter()
            .enumerate()
            .rev()
            .find(|(_, s)| s.droppable)
            .map(|(j, _)| j);
        match drop_idx {
            Some(j) => {
                lines[i].remove(j);
            }
            None => return,
        }
    }
}

/// Drop-to-fit without column alignment.
///
/// Each line is budgeted on its own raw width (segments + separators).
/// Only used by `--no-align`, which trades cross-line tidiness for
/// shorter lines on narrow terminals.
pub fn fit_unaligned(lines: &mut [Vec<Segment>], sep_width: usize, max_cols: Option<usize>) {
    let Some(max) = max_cols else {
        return;
    };
    for line in lines.iter_mut() {
        loop {
            let raw: usize = line.iter().map(Segment::width).sum::<usize>()
                + sep_width * line.len().saturating_sub(1);
            if raw <= max {
                break;
            }
            // Walk from the right and drop the first droppable segment.
            // Anchors stay put, matching the aligned path's contract.
            let drop_idx = line
                .iter()
                .enumerate()
                .rev()
                .find(|(_, s)| s.droppable)
                .map(|(j, _)| j);
            match drop_idx {
                Some(j) => {
                    line.remove(j);
                }
                None => break,
            }
        }
    }
}

/// Width a line will occupy *after* per-column padding is applied. We
/// charge each non-final segment its column's full width, since that's
/// what `write_line` will pad it to.
pub fn aligned_width(line: &[Segment], col_widths: &[usize], sep_width: usize) -> usize {
    if line.is_empty() {
        return 0;
    }
    let last = line.len() - 1;
    let cells: usize = line
        .iter()
        .enumerate()
        .map(|(i, seg)| {
            if i == last {
                seg.width()
            } else {
                col_widths.get(i).copied().unwrap_or(0)
            }
        })
        .sum();
    cells + sep_width * last
}

/// Compute the maximum width seen at each column index across every line.
///
/// Lines with fewer segments simply contribute nothing past their
/// own length, which is the right behavior - we don't want to extend a
/// short line's last column with phantom padding.
pub fn column_widths(lines: &[Vec<Segment>]) -> Vec<usize> {
    let max_cols = lines.iter().map(Vec::len).max().unwrap_or(0);
    (0..max_cols)
        .map(|col| {
            lines
                .iter()
                .filter_map(|line| line.get(col))
                .map(Segment::width)
                .max()
                .unwrap_or(0)
        })
        .collect()
}
