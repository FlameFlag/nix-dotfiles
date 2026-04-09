//! VCS dispatch: walk parents looking for `.jj`, fall back to git, fall back to
//! nothing.

use std::path::{Path, PathBuf};

pub mod git;
pub mod jj;
pub mod jj_prefix;

use crate::render::colors::Palette;
use crate::render::icons::Icons;
use crate::render::segment::Segment;

/// Try to produce the styled VCS info segment for `vcs_dir`. Returns `None`
/// if the directory is neither a jj nor a git working tree (or on any error).
pub fn collect(vcs_dir: &str, icons: &Icons, pal: &Palette) -> Option<Segment> {
    let path = PathBuf::from(vcs_dir);
    let abs = std::fs::canonicalize(&path).unwrap_or(path);

    // jj-lib's `Workspace::load` requires the *workspace root*, not an
    // arbitrary subdirectory inside it. Walk parents until we find the
    // `.jj` marker and hand that path to the jj collector.
    if let Some(jj_root) = find_jj_root(&abs)
        && let Some(s) = jj::collect(&jj_root, icons, pal)
    {
        return Some(s);
    }
    git::collect(&abs, icons, pal)
}

/// Walk parent directories looking for a `.jj` directory and return the
/// directory that contains it (the workspace root).
fn find_jj_root(start: &Path) -> Option<PathBuf> {
    let mut cur: &Path = start;
    loop {
        if cur.join(".jj").is_dir() {
            return Some(cur.to_path_buf());
        }
        match cur.parent() {
            Some(p) if p != cur => cur = p,
            _ => return None,
        }
    }
}
