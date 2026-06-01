use std::collections::HashMap;
use std::io::Read;
use std::path::{Component, Path, PathBuf};

use dotfiles_common::{fs, http::Client, process, template};
use flate2::read::GzDecoder;
use fs_err::File;
use serde::Deserialize;
use thiserror::Error;
use walkdir::WalkDir;
use xz2::read::XzDecoder;

use crate::catalog::{ArchiveAction, ArchiveKind, ArchivePlatform, Link, Source};
use crate::platform::Host;
use crate::progress::Spinner;
use crate::{Context, links, release};

#[derive(Debug, Error)]
pub enum ArchiveError {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Http(#[from] dotfiles_common::http::HttpError),
    #[error(transparent)]
    Process(#[from] process::ProcessError),
    #[error(transparent)]
    Template(#[from] template::TemplateError),
    #[error(transparent)]
    Release(#[from] release::ReleaseError),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Zip(#[from] zip::result::ZipError),
    #[error(transparent)]
    Link(#[from] links::LinkError),
    #[error("unsupported platform")]
    UnsupportedPlatform,
    #[error("source required for archive platform")]
    MissingSource,
    #[error("version index did not contain a release")]
    EmptyVersionIndex,
}

#[derive(Debug)]
pub(crate) struct ResolvedSource {
    pub(crate) version: String,
    pub(crate) url: String,
}

#[derive(Deserialize)]
struct IndexedRelease {
    version: String,
}

/// Installs an archive-backed tool for the current host.
///
/// # Errors
///
/// Returns an error if platform selection, source resolution, download, extraction, or linking fails.
pub fn install_archive(
    ctx: &Context,
    tool: &str,
    action: &ArchiveAction,
) -> Result<(), ArchiveError> {
    let platform = select_platform(action, Host::current())?;
    let source = platform
        .source
        .as_ref()
        .or(action.source.as_ref())
        .ok_or(ArchiveError::MissingSource)?;
    let resolved = resolve_source(source, &platform.platform)?;

    let install_dir = links::install_dir(ctx, tool, &resolved.version);
    let install_dir_text = install_dir.to_string_lossy();
    let mut bindings = HashMap::new();
    bindings.insert("version", resolved.version.as_str());
    bindings.insert("platform", platform.platform.as_str());
    bindings.insert("install_dir", install_dir_text.as_ref());
    let rendered_links = render_links(&platform.links, &bindings)?;
    let rendered_app_links = render_links(&platform.app_links, &bindings)?;

    let temp_dir = install_dir.with_extension("tmp");
    fs::remove_dir_if_exists(&temp_dir)?;
    fs::remove_dir_if_exists(&install_dir)?;

    let download_dir = fs::tmp_dir("bootstrap-archive")?;
    let archive_path = download_dir.path().join(match platform.kind {
        ArchiveKind::TarXz => "archive.tar.xz",
        ArchiveKind::TarGz => "archive.tar.gz",
        ArchiveKind::Zip => "archive.zip",
    });
    let client = Client::new("dotfiles-bootstrap")?;
    let progress = Spinner::new(format!("{tool}: downloading {}", resolved.version));
    client.download_file(&resolved.url, &archive_path)?;
    progress.set_message(format!("{tool}: extracting {}", resolved.version));

    extract_file(
        &archive_path,
        &temp_dir,
        platform.kind,
        platform.strip_components,
    )?;
    progress.set_message(format!("{tool}: repairing executable permissions"));
    repair_executable_permissions(&temp_dir)?;
    progress.set_message(format!("{tool}: installing {}", resolved.version));
    if let Some(parent) = install_dir.parent() {
        fs_err::create_dir_all(parent)?;
    }
    fs_err::rename(&temp_dir, &install_dir)?;
    progress.set_message(format!("{tool}: linking binaries"));
    links::link_many(ctx, tool, &install_dir, &rendered_links)?;
    link_applications(&install_dir, &rendered_app_links)?;
    progress.finish_and_clear();
    Ok(())
}

/// Selects the archive platform matching `host`.
///
/// # Errors
///
/// Returns an error if no platform entry matches the host.
pub fn select_platform(
    action: &ArchiveAction,
    host: Host,
) -> Result<&ArchivePlatform, ArchiveError> {
    action
        .platforms
        .iter()
        .find(|platform| host.matches(platform.when))
        .ok_or(ArchiveError::UnsupportedPlatform)
}

pub(crate) fn resolve_source(
    source: &Source,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    match source {
        Source::GithubLatest {
            repo,
            tag_prefix,
            asset,
        } => resolve_github_latest(repo, tag_prefix, asset, platform),
        Source::GithubLatestMatching {
            repo,
            tag_prefix,
            asset_prefix,
            asset_suffix,
        } => resolve_github_latest_matching(repo, tag_prefix, asset_prefix, asset_suffix, platform),
        Source::Direct { version, url } => resolve_direct(version, url, platform),
        Source::Command { argv, url } => resolve_command(argv, url, platform),
        Source::VersionIndex { index_url, url } => resolve_version_index(index_url, url, platform),
    }
}

fn resolve_github_latest(
    repo: &str,
    tag_prefix: &str,
    asset: &str,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    let release = release::GithubRelease::latest(repo)?;
    let version = release.version(tag_prefix);
    let bindings = source_bindings(&version, platform);
    let asset = template::render(asset, &bindings)?;
    Ok(ResolvedSource {
        version,
        url: release.asset_url(&asset)?,
    })
}

fn resolve_github_latest_matching(
    repo: &str,
    tag_prefix: &str,
    asset_prefix: &str,
    asset_suffix: &str,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    let release = release::GithubRelease::latest(repo)?;
    let version = release.version(tag_prefix);
    let bindings = source_bindings(&version, platform);
    let prefix = template::render(asset_prefix, &bindings)?;
    let suffix = template::render(asset_suffix, &bindings)?;
    Ok(ResolvedSource {
        version,
        url: release.matching_asset_url(&prefix, &suffix)?,
    })
}

fn resolve_direct(
    version: &str,
    url: &str,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    let bindings = source_bindings(version, platform);
    Ok(ResolvedSource {
        version: version.to_owned(),
        url: template::render(url, &bindings)?,
    })
}

fn resolve_command(
    argv: &[String],
    url: &str,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    let version = process::trimmed_text(argv)?;
    let bindings = source_bindings(&version, platform);
    let url = template::render(url, &bindings)?;
    Ok(ResolvedSource { version, url })
}

fn resolve_version_index(
    index_url: &str,
    url: &str,
    platform: &str,
) -> Result<ResolvedSource, ArchiveError> {
    let client = Client::new("dotfiles-bootstrap")?;
    let releases: Vec<IndexedRelease> = client.json(index_url)?;
    let version = releases
        .into_iter()
        .next()
        .ok_or(ArchiveError::EmptyVersionIndex)?
        .version;
    let bindings = source_bindings(&version, platform);
    let url = template::render(url, &bindings)?;
    Ok(ResolvedSource { version, url })
}

fn source_bindings<'a>(version: &'a str, platform: &'a str) -> template::Bindings<'a> {
    let mut bindings = HashMap::new();
    bindings.insert("version", version);
    bindings.insert("platform", platform);
    bindings
}

pub(crate) fn render_links(
    links: &[Link],
    bindings: &template::Bindings<'_>,
) -> Result<Vec<Link>, ArchiveError> {
    links
        .iter()
        .map(|link| {
            Ok(Link {
                name: template::render(&link.name, bindings)?,
                path: template::render(&link.path, bindings)?,
                env: link
                    .env
                    .iter()
                    .map(|env| {
                        Ok(crate::catalog::EnvVar {
                            name: template::render(&env.name, bindings)?,
                            value: template::render(&env.value, bindings)?,
                        })
                    })
                    .collect::<Result<Vec<_>, ArchiveError>>()?,
            })
        })
        .collect()
}

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
        let Some(path) = stripped_path(entry.path()?.as_ref(), strip_components) else {
            continue;
        };
        let out_path = dest_path.join(path);
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
                create_zip_symlink(&mut file, &out_path)?;
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
    out_path: &Path,
) -> Result<(), ArchiveError> {
    use std::ffi::OsStr;
    use std::os::unix::ffi::OsStrExt;

    let mut target = Vec::with_capacity(file.size().try_into().unwrap_or(0));
    file.read_to_end(&mut target)?;
    std::os::unix::fs::symlink(OsStr::from_bytes(&target), out_path)?;
    Ok(())
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

fn repair_executable_permissions(root: &Path) -> Result<(), ArchiveError> {
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

fn link_applications(install_dir: &Path, entries: &[Link]) -> Result<(), ArchiveError> {
    #[cfg(not(target_os = "macos"))]
    let _ = (install_dir, entries);

    #[cfg(target_os = "macos")]
    {
        for entry in entries {
            let target = install_dir.join(&entry.path);
            let link_path = Path::new("/Applications").join(&entry.name);
            if link_path.exists() {
                match fs_err::read_link(&link_path) {
                    Ok(_) => fs_err::remove_file(&link_path)?,
                    Err(_) => continue,
                }
            }
            std::os::unix::fs::symlink(&target, &link_path)?;
            process::run(&[
                "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
                    .into(),
                "-f".into(),
                link_path.to_string_lossy().into_owned(),
            ])?;
        }
    }
    Ok(())
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
    fn resolves_direct_sources_and_renders_links() -> Result<(), ArchiveError> {
        let source = Source::Direct {
            version: "1.2.3".into(),
            url: "https://example.invalid/{version}/{platform}/tool.tar.gz".into(),
        };
        let resolved = resolve_source(&source, "aarch64-test")?;
        assert_eq!(resolved.version, "1.2.3");
        assert_eq!(
            resolved.url,
            "https://example.invalid/1.2.3/aarch64-test/tool.tar.gz"
        );

        let mut bindings = HashMap::new();
        bindings.insert("version", "1.2.3");
        bindings.insert("platform", "aarch64-test");
        let links = render_links(
            &[Link {
                name: "tool-{version}".into(),
                path: "bin/{platform}/tool".into(),
                env: vec![crate::catalog::EnvVar {
                    name: "TOOL_VERSION".into(),
                    value: "{version}".into(),
                }],
            }],
            &bindings,
        )?;

        assert_eq!(links[0].name, "tool-1.2.3");
        assert_eq!(links[0].path, "bin/aarch64-test/tool");
        assert_eq!(links[0].env[0].name, "TOOL_VERSION");
        assert_eq!(links[0].env[0].value, "1.2.3");
        Ok(())
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
}
