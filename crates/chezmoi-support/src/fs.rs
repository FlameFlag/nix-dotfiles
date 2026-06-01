use std::path::{Path, PathBuf};

use crate::error::{Error, Result};

pub fn first_dir(path: &Path) -> Result<PathBuf> {
    for entry in fs_err::read_dir(path)? {
        let entry = entry?;
        if entry.file_type()?.is_dir() {
            return Ok(entry.path());
        }
    }
    Err(Error::CommandFailed(
        "archive did not contain a root directory".into(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn first_dir_returns_directory_and_rejects_empty_archives() -> Result<()> {
        let temp = tempfile::tempdir()?;
        fs_err::write(temp.path().join("file.txt"), "not a dir")?;
        let dir = temp.path().join("root");
        fs_err::create_dir(&dir)?;

        assert_eq!(first_dir(temp.path())?, dir);

        let empty = tempfile::tempdir()?;
        assert!(matches!(
            first_dir(empty.path()),
            Err(Error::CommandFailed(message)) if message.contains("root directory")
        ));
        Ok(())
    }
}
