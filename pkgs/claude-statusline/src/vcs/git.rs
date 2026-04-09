//! Git collector: build the styled VCS info segment via `gix`.
//!
//! Branch / detached-head display, ahead/behind arrows, in-progress
//! operations (merge/rebase/etc.), staged/unstaged/untracked indicators,
//! and stash count.

use std::path::Path;

use gix::bstr::BString;
use gix::status::Item as StatusItem;
use gix::status::index_worktree;

use crate::render::colors::Palette;
use crate::render::icons::Icons;
use crate::render::segment::Segment;

pub fn collect(dir: &Path, icons: &Icons, pal: &Palette) -> Option<Segment> {
    // Disable optional file locks - read-only operations shouldn't
    // contend with concurrent git processes.
    // SAFETY: single-threaded init time, called before any threads are spawned.
    #[allow(unsafe_code)]
    unsafe {
        std::env::set_var("GIT_OPTIONAL_LOCKS", "0");
    }

    let repo = gix::open(dir).ok()?;
    let mut s = Segment::new(true);

    // Branch / oid.
    let head_ref = repo.head_ref().ok().flatten();
    let head_id = repo.head_id().ok();
    let branch_name: Option<String> = head_ref.as_ref().map(|r| r.name().shorten().to_string());

    let short_hash = head_id.as_ref().map(|id| id.to_hex_with_len(7).to_string());

    if !icons.git.is_empty() {
        s.push_plain(format!("{} ", icons.git));
    }

    match (branch_name.as_deref(), short_hash.as_deref()) {
        (Some(b), Some(h)) => {
            s.push_styled(b.to_string(), pal.magenta);
            s.push_plain(" ");
            s.push_styled(h.to_string(), pal.dim);
        }
        (Some(b), None) => {
            s.push_styled(b.to_string(), pal.magenta);
            s.push_plain(" ");
            s.push_styled("(no commits)", pal.dim);
        }
        (None, Some(h)) => {
            s.push_styled("(detached)", pal.yellow);
            s.push_plain(" ");
            s.push_styled(h.to_string(), pal.dim);
        }
        (None, None) => {}
    }

    // Ahead / behind upstream.
    let tracking = upstream_divergence(&repo);
    let arrows: Vec<(&str, usize)> = [
        (icons.ahead, tracking.ahead),
        (icons.behind, tracking.behind),
    ]
    .into_iter()
    .filter(|(_, n)| *n > 0)
    .collect();
    if !arrows.is_empty() {
        s.push_plain(" ");
        for (i, (icon, n)) in arrows.iter().enumerate() {
            if i > 0 {
                s.push_plain(" ");
            }
            s.push_styled(format!("{icon}{n}"), pal.cyan);
        }
    }

    // In-progress operation.
    if let Some(state) = repo.state() {
        use gix::state::InProgress::{
            ApplyMailbox, ApplyMailboxRebase, Bisect, CherryPick, CherryPickSequence, Merge,
            Rebase, RebaseInteractive, Revert, RevertSequence,
        };
        let label: Option<String> = match state {
            Merge => Some(format!("{} merge", icons.merge)),
            Rebase | RebaseInteractive | ApplyMailbox | ApplyMailboxRebase => {
                Some(format!("{} rebase", icons.rebase))
            }
            CherryPick | CherryPickSequence => Some(format!("{} cherry-pick", icons.cherry_pick)),
            Revert | RevertSequence => Some(format!("{} revert", icons.revert)),
            Bisect => Some(format!("{} bisect", icons.bisect)),
        };
        if let Some(l) = label {
            s.push_plain(" ");
            s.push_styled(l, pal.red);
        }
    }

    // Status indicators (staged / unstaged / untracked).
    match compute_status(&repo) {
        Some(status) => {
            if status.staged {
                s.push_plain(" ");
                s.push_styled(icons.staged.to_string(), pal.green);
            }
            if status.unstaged {
                s.push_plain(" ");
                s.push_styled(icons.dirty.to_string(), pal.yellow);
            } else if !status.staged && !status.untracked {
                s.push_plain(" ");
                s.push_styled(icons.clean.to_string(), pal.green);
            }
            if status.untracked {
                s.push_plain(" ");
                s.push_styled(icons.untracked.to_string(), pal.dim);
            }
        }
        None => {
            s.push_plain(" ");
            s.push_styled(icons.untracked.to_string(), pal.dim);
        }
    }

    // Stash count (read .git/logs/refs/stash).
    let stash_count = count_stash(&repo);
    if stash_count > 0 {
        s.push_plain(" ");
        s.push_styled(format!("{}{stash_count}", icons.stash), pal.dim);
    }

    if s.is_empty() { None } else { Some(s) }
}

/// Working-tree status flags, mutated as `compute_status` walks the
/// gix status iterator.
#[derive(Debug, Default)]
struct GitStatus {
    staged: bool,
    unstaged: bool,
    untracked: bool,
}

/// Ahead/behind counts vs the configured upstream. Defaults to zero so
/// callers don't need to special-case "no upstream configured".
#[derive(Debug, Default)]
struct Tracking {
    ahead: usize,
    behind: usize,
}

#[allow(clippy::literal_string_with_formatting_args)]
fn upstream_divergence(repo: &gix::Repository) -> Tracking {
    let (Ok(head), Ok(upstream)) = (
        repo.rev_parse_single("HEAD"),
        repo.rev_parse_single("HEAD@{upstream}"),
    ) else {
        return Tracking::default();
    };
    let head_oid = head.detach();
    let up_oid = upstream.detach();
    let count_walk = |from, hide| {
        repo.rev_walk([from])
            .with_hidden([hide])
            .all()
            .ok()
            .map_or(0, |w| w.filter_map(Result::ok).count())
    };
    Tracking {
        ahead: count_walk(head_oid, up_oid),
        behind: count_walk(up_oid, head_oid),
    }
}

fn compute_status(repo: &gix::Repository) -> Option<GitStatus> {
    let mut status = GitStatus::default();

    let platform = repo.status(gix::progress::Discard).ok()?;
    let iter = platform.into_iter(Vec::<BString>::new()).ok()?;

    for item in iter.filter_map(Result::ok) {
        match item {
            StatusItem::TreeIndex(_) => status.staged = true,
            StatusItem::IndexWorktree(iw) => match iw {
                index_worktree::Item::Modification { .. }
                | index_worktree::Item::Rewrite { .. } => status.unstaged = true,
                index_worktree::Item::DirectoryContents { entry, .. } => {
                    use gix::dir::entry::Status;
                    if matches!(entry.status, Status::Untracked) {
                        status.untracked = true;
                    }
                }
            },
        }
        if status.staged && status.unstaged && status.untracked {
            break;
        }
    }

    Some(status)
}

fn count_stash(repo: &gix::Repository) -> usize {
    let Ok(reference) = repo.find_reference("refs/stash") else {
        return 0;
    };
    let mut log_iter = reference.log_iter();
    let Ok(Some(iter)) = log_iter.all() else {
        return 0;
    };
    iter.filter_map(Result::ok).count()
}
