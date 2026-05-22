use std::path::{Path, PathBuf};

use crate::error::{Error, Result};

pub fn write_text_if_changed(path: &Path, text: &str) -> Result<bool> {
    if fs_err::read_to_string(path).is_ok_and(|current| current == text) {
        return Ok(false);
    }
    if let Some(parent) = path.parent() {
        fs_err::create_dir_all(parent)?;
    }
    fs_err::write(path, text)?;
    Ok(true)
}

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
    fn write_text_if_changed_reports_changes() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("nested").join("file.txt");

        assert!(write_text_if_changed(&path, "hello")?);
        assert!(!write_text_if_changed(&path, "hello")?);
        assert!(write_text_if_changed(&path, "goodbye")?);
        assert_eq!(fs_err::read_to_string(path)?, "goodbye");
        Ok(())
    }

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
