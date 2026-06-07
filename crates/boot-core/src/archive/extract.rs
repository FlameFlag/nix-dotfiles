use std::io::Read;
use std::path::{Component, Path, PathBuf};

use dotfiles_common::fs;
use flate2::read::GzDecoder;
use fs_err::File;
use walkdir::WalkDir;
use xz2::read::XzDecoder;

use crate::archive::ArchiveError;
use crate::catalog::ArchiveKind;

/// Extracts an archive file into `dest_path`.
///
/// # Errors
///
/// Returns an error if creating directories or reading/extracting archive contents fails.
pub fn extract_file(
    archive_path: &Path,
    dest_path: &Path,
    kind: ArchiveKind,
    strip_components: usize,
) -> Result<(), ArchiveError> {
    fs_err::create_dir_all(dest_path)?;
    match kind {
        ArchiveKind::TarGz => {
            let file = File::open(archive_path)?;
            extract_tar(GzDecoder::new(file), dest_path, strip_components)?;
        }
        ArchiveKind::TarXz => {
            let file = File::open(archive_path)?;
            extract_tar(XzDecoder::new(file), dest_path, strip_components)?;
        }
        ArchiveKind::Zip => extract_zip(archive_path, dest_path, strip_components)?,
    }
    Ok(())
}

fn extract_tar<R: Read>(
    reader: R,
    dest_path: &Path,
    strip_components: usize,
) -> Result<(), ArchiveError> {
    let mut archive = tar::Archive::new(reader);
    for entry in archive.entries()? {
        let mut entry = entry?;
        if strip_components == 0 {
            if !entry.unpack_in(dest_path)? {
                return Err(ArchiveError::UnsafePath(
                    entry.path().unwrap_or_default().into_owned(),
                ));
            }
            continue;
        }
        let Some(path) = stripped_path(entry.path()?.as_ref(), strip_components) else {
            continue;
        };
        let out_path = dest_path.join(path);
        ensure_safe_output_path(dest_path, &out_path)?;
        let entry_type = entry.header().entry_type();
        if entry_type.is_symlink() {
            let target = entry
                .link_name()?
                .ok_or_else(|| ArchiveError::UnsafePath(out_path.clone()))?;
            ensure_safe_link_target(dest_path, &out_path, target.as_ref())?;
        } else if entry_type.is_hard_link() {
            let target = entry
                .link_name()?
                .ok_or_else(|| ArchiveError::UnsafePath(out_path.clone()))?;
            let Some(target) = stripped_path(target.as_ref(), strip_components) else {
                return Err(ArchiveError::UnsafePath(out_path));
            };
            let link_source = dest_path.join(target);
            ensure_safe_output_path(dest_path, &link_source)?;
            if let Some(parent) = out_path.parent() {
                fs_err::create_dir_all(parent)?;
            }
            fs_err::hard_link(link_source, out_path)?;
            continue;
        }
        if let Some(parent) = out_path.parent() {
            fs_err::create_dir_all(parent)?;
        }
        entry.unpack(out_path)?;
    }
    Ok(())
}

fn extract_zip(
    archive_path: &Path,
    dest_path: &Path,
    strip_components: usize,
) -> Result<(), ArchiveError> {
    let file = File::open(archive_path)?;
    let mut archive = zip::ZipArchive::new(file)?;
    for index in 0..archive.len() {
        let mut file = archive.by_index(index)?;
        let Some(enclosed) = file.enclosed_name() else {
            continue;
        };
        let Some(path) = stripped_path(&enclosed, strip_components) else {
            continue;
        };
        let out_path = dest_path.join(path);
        ensure_safe_output_path(dest_path, &out_path)?;
        if file.is_dir() {
            fs_err::create_dir_all(&out_path)?;
        } else {
            if let Some(parent) = out_path.parent() {
                fs_err::create_dir_all(parent)?;
            }
            #[cfg(unix)]
            if file.is_symlink() {
                if let Some(parent) = out_path.parent() {
                    fs_err::create_dir_all(parent)?;
                }
                create_zip_symlink(&mut file, dest_path, &out_path)?;
                continue;
            }
            let mut out = File::create(&out_path)?;
            std::io::copy(&mut file, &mut out)?;
        }
    }
    Ok(())
}

#[cfg(unix)]
fn create_zip_symlink<R: std::io::Read + ?Sized>(
    file: &mut zip::read::ZipFile<'_, R>,
    root: &Path,
    out_path: &Path,
) -> Result<(), ArchiveError> {
    use std::ffi::OsStr;
    use std::os::unix::ffi::OsStrExt;

    let mut target = Vec::with_capacity(file.size().try_into().unwrap_or(0));
    file.read_to_end(&mut target)?;
    let target = OsStr::from_bytes(&target);
    ensure_safe_link_target(root, out_path, Path::new(target))?;
    std::os::unix::fs::symlink(target, out_path)?;
    Ok(())
}

fn ensure_safe_output_path(root: &Path, out_path: &Path) -> Result<(), ArchiveError> {
    let relative = out_path
        .strip_prefix(root)
        .map_err(|_| ArchiveError::UnsafePath(out_path.to_path_buf()))?;
    let mut current = root.to_path_buf();
    for component in relative.components() {
        if !matches!(component, Component::Normal(_)) {
            return Err(ArchiveError::UnsafePath(out_path.to_path_buf()));
        }
        current.push(component.as_os_str());
        match fs_err::symlink_metadata(&current) {
            Ok(metadata) if metadata.file_type().is_symlink() => {
                return Err(ArchiveError::UnsafePath(current));
            }
            Ok(_) => {}
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {}
            Err(err) => return Err(err.into()),
        }
    }
    Ok(())
}

fn ensure_safe_link_target(
    root: &Path,
    link_path: &Path,
    target: &Path,
) -> Result<(), ArchiveError> {
    if target.is_absolute() {
        return Err(ArchiveError::UnsafePath(link_path.to_path_buf()));
    }
    let parent = link_path
        .parent()
        .ok_or_else(|| ArchiveError::UnsafePath(link_path.to_path_buf()))?;
    let root = fs::normalize(root);
    let target = fs::normalize(&parent.join(target));
    if target.starts_with(root) {
        Ok(())
    } else {
        Err(ArchiveError::UnsafePath(link_path.to_path_buf()))
    }
}

fn stripped_path(path: &Path, strip_components: usize) -> Option<PathBuf> {
    // Treat only normal path components as archive payload. This strips roots,
    // prefixes, `.` and `..` entries so tar and zip extraction cannot write
    // outside `dest_path`, then applies the catalog's strip count.
    let mut components = path
        .components()
        .filter(|component| matches!(component, Component::Normal(_)))
        .skip(strip_components)
        .peekable();
    components.peek()?;
    Some(components.collect())
}

pub(super) fn repair_executable_permissions(root: &Path) -> Result<(), ArchiveError> {
    if cfg!(windows) {
        return Ok(());
    }
    for entry in WalkDir::new(root) {
        let entry = entry.map_err(std::io::Error::other)?;
        // Zip archives often lose mode bits. Restore executability for the
        // binary formats and scripts this bootstrapper installs.
        if entry.file_type().is_file() && has_executable_header(entry.path())? {
            fs::make_executable(entry.path())?;
        }
    }
    Ok(())
}

fn has_executable_header(path: &Path) -> Result<bool, ArchiveError> {
    let mut file = File::open(path)?;
    let mut bytes = [0_u8; 4];
    let read = file.read(&mut bytes)?;
    let bytes = &bytes[..read];
    Ok(bytes.starts_with(b"#!")
        || bytes.starts_with(b"\x7fELF")
        || bytes.starts_with(b"MZ")
        || matches!(
            u32::from_be_bytes(pad4(bytes)),
            0xfeed_face | 0xfeed_facf | 0xcafe_babe | 0xcafe_babf
        )
        || matches!(u32::from_le_bytes(pad4(bytes)), 0xfeed_face | 0xfeed_facf))
}

fn pad4(bytes: &[u8]) -> [u8; 4] {
    let mut out = [0; 4];
    out[..bytes.len().min(4)].copy_from_slice(&bytes[..bytes.len().min(4)]);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn strips_components_safely() {
        assert_eq!(
            stripped_path(Path::new("root/bin/tool"), 1),
            Some(PathBuf::from("bin/tool"))
        );
        assert!(stripped_path(Path::new("root"), 1).is_none());
        assert_eq!(
            stripped_path(Path::new("../root/bin"), 1),
            Some(PathBuf::from("bin"))
        );
    }

    #[test]
    fn executable_headers_detect_scripts_and_binaries() -> Result<(), ArchiveError> {
        let temp = fs::tmp_dir("bootstrap-executable-header-test")?;
        let script = temp.path().join("script");
        let elf = temp.path().join("elf");
        let text = temp.path().join("text");
        fs_err::write(&script, b"#!/bin/sh\n")?;
        fs_err::write(&elf, b"\x7fELF")?;
        fs_err::write(&text, b"plain text")?;

        assert!(has_executable_header(&script)?);
        assert!(has_executable_header(&elf)?);
        assert!(!has_executable_header(&text)?);
        Ok(())
    }

    #[test]
    fn extract_file_handles_tar_gz_and_repairs_script_permissions() -> Result<(), ArchiveError> {
        let temp = fs::tmp_dir("bootstrap-tar-gz-test")?;
        let archive_path = temp.path().join("archive.tar.gz");
        let archive_file = File::create(&archive_path)?;
        let encoder = flate2::write::GzEncoder::new(archive_file, flate2::Compression::default());
        let mut archive = tar::Builder::new(encoder);
        let bytes = b"#!/bin/sh\nexit 0\n";
        let mut header = tar::Header::new_gnu();
        header.set_path("root/bin/demo")?;
        header.set_size(bytes.len().try_into().unwrap_or(0));
        header.set_mode(0o644);
        header.set_cksum();
        archive.append(&header, &bytes[..])?;
        let encoder = archive.into_inner()?;
        encoder.finish()?;

        let dest = temp.path().join("dest");
        extract_file(&archive_path, &dest, ArchiveKind::TarGz, 1)?;
        repair_executable_permissions(&dest)?;

        let script = dest.join("bin/demo");
        assert_eq!(fs_err::read_to_string(&script)?, "#!/bin/sh\nexit 0\n");
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let mode = fs_err::metadata(&script)?.permissions().mode();
            assert_ne!(mode & 0o111, 0);
        }
        Ok(())
    }

    #[cfg(unix)]
    #[test]
    fn tar_extraction_rejects_symlink_escape() -> Result<(), ArchiveError> {
        let temp = fs::tmp_dir("bootstrap-tar-symlink-escape-test")?;
        let outside = temp.path().join("outside");
        fs_err::create_dir_all(&outside)?;
        let archive_path = temp.path().join("archive.tar.gz");
        let archive_file = File::create(&archive_path)?;
        let encoder = flate2::write::GzEncoder::new(archive_file, flate2::Compression::default());
        let mut archive = tar::Builder::new(encoder);

        let mut link_header = tar::Header::new_gnu();
        link_header.set_entry_type(tar::EntryType::Symlink);
        link_header.set_size(0);
        link_header.set_cksum();
        archive.append_link(&mut link_header, "root/link", &outside)?;

        let bytes = b"escaped";
        let mut file_header = tar::Header::new_gnu();
        file_header.set_path("root/link/escaped.txt")?;
        file_header.set_size(bytes.len().try_into().unwrap_or(0));
        file_header.set_cksum();
        archive.append(&file_header, &bytes[..])?;
        let encoder = archive.into_inner()?;
        encoder.finish()?;

        let dest = temp.path().join("dest");
        let result = extract_file(&archive_path, &dest, ArchiveKind::TarGz, 1);

        assert!(matches!(result, Err(ArchiveError::UnsafePath(_))));
        assert!(!outside.join("escaped.txt").exists());
        Ok(())
    }

    #[test]
    fn extract_file_handles_zip_archives() -> Result<(), ArchiveError> {
        let temp = fs::tmp_dir("bootstrap-zip-test")?;
        let archive_path = temp.path().join("archive.zip");
        let archive_file = File::create(&archive_path)?;
        let mut writer = zip::ZipWriter::new(archive_file);
        writer.start_file("root/bin/tool", zip::write::SimpleFileOptions::default())?;
        use std::io::Write;
        writer.write_all(b"tool")?;
        writer.finish()?;

        let dest = temp.path().join("dest");
        extract_file(&archive_path, &dest, ArchiveKind::Zip, 1)?;

        assert_eq!(fs_err::read_to_string(dest.join("bin/tool"))?, "tool");
        Ok(())
    }

    #[cfg(unix)]
    #[test]
    fn zip_extraction_preserves_symlinks() -> Result<(), ArchiveError> {
        let temp = fs::tmp_dir("bootstrap-zip-symlink-test")?;
        let archive_path = temp.path().join("archive.zip");
        let archive_file = File::create(&archive_path)?;
        let mut writer = zip::ZipWriter::new(archive_file);
        writer.add_symlink(
            "root/Visual Studio Code.app/Contents/MacOS/Electron",
            "Code",
            zip::write::SimpleFileOptions::default(),
        )?;
        writer.finish()?;

        let dest = temp.path().join("dest");
        extract_zip(&archive_path, &dest, 1)?;
        let link_path = dest.join("Visual Studio Code.app/Contents/MacOS/Electron");

        assert!(
            fs_err::symlink_metadata(&link_path)?
                .file_type()
                .is_symlink()
        );
        assert_eq!(fs_err::read_link(link_path)?, PathBuf::from("Code"));
        Ok(())
    }

    #[cfg(unix)]
    #[test]
    fn zip_extraction_rejects_symlink_escape() -> Result<(), ArchiveError> {
        let temp = fs::tmp_dir("bootstrap-zip-symlink-escape-test")?;
        let outside = temp.path().join("outside");
        fs_err::create_dir_all(&outside)?;
        let archive_path = temp.path().join("archive.zip");
        let archive_file = File::create(&archive_path)?;
        let mut writer = zip::ZipWriter::new(archive_file);
        let outside_text = outside.to_string_lossy();
        writer.add_symlink(
            "root/link",
            outside_text.as_ref(),
            zip::write::SimpleFileOptions::default(),
        )?;
        writer.start_file(
            "root/link/escaped.txt",
            zip::write::SimpleFileOptions::default(),
        )?;
        use std::io::Write;
        writer.write_all(b"escaped")?;
        writer.finish()?;

        let dest = temp.path().join("dest");
        let result = extract_zip(&archive_path, &dest, 1);

        assert!(matches!(result, Err(ArchiveError::UnsafePath(_))));
        assert!(!outside.join("escaped.txt").exists());
        Ok(())
    }
}
