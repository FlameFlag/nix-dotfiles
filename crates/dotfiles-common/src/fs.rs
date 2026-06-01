use std::io::Write;
use std::path::{Component, Path, PathBuf};

use fs_err as fs;

/// Writes bytes to a file and marks it executable.
///
/// # Errors
///
/// Returns an error if creating parent directories, writing the file, or updating permissions fails.
pub fn write_executable(path: impl AsRef<Path>, bytes: &[u8]) -> std::io::Result<()> {
    let path = path.as_ref();
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let mut file = fs::File::create(path)?;
    file.write_all(bytes)?;
    make_executable(path)?;
    Ok(())
}

/// Writes text to a file only when the current contents differ.
///
/// Parent directories are created automatically. The return value indicates
/// whether the file contents changed.
///
/// # Errors
///
/// Returns an error if reading, creating parent directories, or writing fails.
pub fn write_text_if_changed(path: impl AsRef<Path>, text: &str) -> std::io::Result<bool> {
    let path = path.as_ref();
    if fs::read_to_string(path).is_ok_and(|current| current == text) {
        return Ok(false);
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    fs::write(path, text)?;
    Ok(true)
}

/// Marks a file executable on Unix platforms.
///
/// # Errors
///
/// Returns an error if reading or updating permissions fails.
pub fn make_executable(path: impl AsRef<Path>) -> std::io::Result<()> {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let metadata = fs::metadata(path.as_ref())?;
        let mut permissions = metadata.permissions();
        permissions.set_mode(permissions.mode() | 0o755);
        fs::set_permissions(path, permissions)?;
    }
    #[cfg(not(unix))]
    {
        let _ = path.as_ref();
    }
    Ok(())
}

/// Removes a directory tree if it exists.
///
/// # Errors
///
/// Returns an error if removal fails for a reason other than the directory being absent.
pub fn remove_dir_if_exists(path: impl AsRef<Path>) -> std::io::Result<()> {
    match fs::remove_dir_all(path.as_ref()) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(err),
    }
}

/// Recursively copies `src` into `dst`, creating parent directories as needed.
///
/// # Errors
///
/// Returns an error if walking, creating, or copying any directory entry fails.
pub fn copy_dir_recursive(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs_more::directory::copy_directory(
        src,
        dst,
        fs_more::directory::DirectoryCopyOptions::default(),
    )
    .map(drop)
    .map_err(std::io::Error::other)
}

/// Moves `src` to `dst`, falling back to copy-and-delete when rename cannot be used.
///
/// # Errors
///
/// Returns an error if source/destination validation, renaming, copying, or cleanup fails.
pub fn move_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    fs_more::directory::move_directory(
        src,
        dst,
        fs_more::directory::DirectoryMoveOptions::default(),
    )
    .map(drop)
    .map_err(std::io::Error::other)
}

/// Creates a temporary directory with the supplied prefix.
///
/// # Errors
///
/// Returns an error if the temporary directory cannot be created.
pub fn tmp_dir(prefix: &str) -> std::io::Result<tempfile::TempDir> {
    tempfile::Builder::new().prefix(prefix).tempdir()
}

/// Returns whether `path` normalizes under `root` without touching the filesystem.
///
/// This is lexical rather than canonical: it works for paths that do not exist yet,
/// but it does not resolve symlinks.
pub fn relative_under(root: impl AsRef<Path>, path: impl AsRef<Path>) -> bool {
    let root = normalize(root.as_ref());
    let path = normalize(path.as_ref());
    path.starts_with(root)
}

/// Lexically normalizes `.` and `..` components while preserving nonexistent paths.
#[must_use]
pub fn normalize(path: &Path) -> PathBuf {
    let mut normalized = if path.is_absolute() {
        PathBuf::new()
    } else {
        std::env::current_dir().unwrap_or_else(|_| PathBuf::from("."))
    };

    for component in path.components() {
        match component {
            Component::Prefix(_) | Component::RootDir | Component::Normal(_) => {
                normalized.push(component.as_os_str());
            }
            Component::CurDir => {}
            Component::ParentDir => {
                if !normalized.pop() {
                    normalized.push(component.as_os_str());
                }
            }
        }
    }

    normalized
}

/// Interprets UTF-8 bytes as text and trims only ASCII whitespace.
///
/// Invalid UTF-8 is treated as an empty string because callers use this on
/// command output and sysfs-like byte streams where a lossy fallback would hide
/// malformed data.
#[must_use]
pub fn trim_ascii_whitespace(bytes: &[u8]) -> &str {
    let text = std::str::from_utf8(bytes).unwrap_or("");
    text.trim_matches(|c: char| c.is_ascii_whitespace())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn relative_under_handles_dot_segments() {
        let root = std::env::temp_dir().join("root");

        assert!(relative_under(&root, root.join("./child/../child")));
    }

    #[test]
    fn relative_under_rejects_parent_escape() {
        let root = std::env::temp_dir().join("root");

        assert!(!relative_under(&root, root.join("../other")));
    }

    #[test]
    fn write_executable_creates_parent_and_marks_file() {
        let temp = tempfile::tempdir().expect("tempdir");
        let path = temp.path().join("bin").join("demo");

        write_executable(&path, b"hello").expect("write executable");

        assert_eq!(fs::read(&path).expect("read file"), b"hello");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs::metadata(&path).expect("metadata").permissions().mode();
            assert_ne!(mode & 0o111, 0);
        }
    }

    #[test]
    fn write_text_if_changed_reports_changes() {
        let temp = tempfile::tempdir().expect("tempdir");
        let path = temp.path().join("nested").join("file.txt");

        assert!(write_text_if_changed(&path, "hello").expect("write hello"));
        assert!(!write_text_if_changed(&path, "hello").expect("skip unchanged"));
        assert!(write_text_if_changed(&path, "goodbye").expect("write goodbye"));
        assert_eq!(fs::read_to_string(path).expect("read file"), "goodbye");
    }

    #[test]
    fn copy_dir_recursive_copies_nested_files() {
        let temp = tempfile::tempdir().expect("tempdir");
        let src = temp.path().join("src");
        let dst = temp.path().join("dst");
        fs::create_dir_all(src.join("nested")).expect("create nested source");
        fs::write(src.join("root.txt"), "root").expect("write root");
        fs::write(src.join("nested").join("leaf.txt"), "leaf").expect("write leaf");

        copy_dir_recursive(&src, &dst).expect("copy tree");

        assert_eq!(
            fs::read_to_string(dst.join("root.txt")).expect("read root"),
            "root"
        );
        assert_eq!(
            fs::read_to_string(dst.join("nested").join("leaf.txt")).expect("read leaf"),
            "leaf"
        );
    }

    #[test]
    fn move_dir_moves_nested_files() {
        let temp = tempfile::tempdir().expect("tempdir");
        let src = temp.path().join("src");
        let dst = temp.path().join("dst");
        fs::create_dir_all(src.join("nested")).expect("create nested source");
        fs::write(src.join("nested").join("leaf.txt"), "leaf").expect("write leaf");

        move_dir(&src, &dst).expect("move tree");

        assert!(!src.exists());
        assert_eq!(
            fs::read_to_string(dst.join("nested").join("leaf.txt")).expect("read leaf"),
            "leaf"
        );
    }
}
