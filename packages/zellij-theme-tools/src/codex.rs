use std::ffi::OsString;
use std::path::{Path, PathBuf};

use directories::BaseDirs;

use crate::{Error, Result};

/// Finds the Codex executable.
///
/// # Errors
///
/// Returns an error if Codex cannot be found or the home directory is unavailable.
pub fn codex_bin() -> Result<PathBuf> {
    let home = home_dir()?;
    codex_bin_from(
        &home,
        std::env::var_os("ZELLIJ_THEME_RUN_CODEX_BIN")
            .or_else(|| std::env::var_os("CODEX_ZELLIJ_THEME_CODEX_BIN")),
        || which::which("codex").ok(),
    )
}

fn codex_bin_from(
    home: &Path,
    configured_path: Option<OsString>,
    find_on_path: impl FnOnce() -> Option<PathBuf>,
) -> Result<PathBuf> {
    if let Some(path) = configured_path
        .map(PathBuf::from)
        .filter(|path| path.is_file())
    {
        return Ok(path);
    }

    if let Some(path) = find_on_path() {
        return Ok(path);
    }
    for candidate in [".bun/bin/codex", ".npm/bin/codex", ".local/bin/codex"] {
        let path = home.join(candidate);
        if path.is_file() {
            return Ok(path);
        }
    }
    Err(Error::CodexNotFound)
}

/// Returns the current user's home directory.
///
/// # Errors
///
/// Returns an error if the home directory cannot be determined.
pub fn home_dir() -> Result<PathBuf> {
    BaseDirs::new()
        .map(|dirs| dirs.home_dir().to_path_buf())
        .ok_or(Error::HomeMissing)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codex_bin_prefers_configured_existing_file() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let configured = temp.path().join("configured-codex");
        let path_codex = temp.path().join("path-codex");
        fs_err::write(&configured, "")?;
        fs_err::write(&path_codex, "")?;

        assert_eq!(
            codex_bin_from(
                temp.path(),
                Some(configured.clone().into_os_string()),
                || { Some(path_codex) }
            )?,
            configured
        );
        Ok(())
    }

    #[test]
    fn codex_bin_uses_home_candidates_and_path_fallback() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path_codex = temp.path().join("path-codex");
        fs_err::write(&path_codex, "")?;

        assert_eq!(
            codex_bin_from(temp.path(), None, || Some(path_codex.clone()))?,
            path_codex
        );

        let bun_codex = temp.path().join(".bun/bin/codex");
        fs_err::create_dir_all(bun_codex.parent().expect("parent"))?;
        fs_err::write(&bun_codex, "")?;
        assert_eq!(codex_bin_from(temp.path(), None, || None)?, bun_codex);
        Ok(())
    }
}
