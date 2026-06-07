use std::collections::HashMap;
use std::path::{Path, PathBuf};

use dotfiles_common::{fs, http::Client, process, template};
use thiserror::Error;

use crate::catalog::{ArchiveAction, ArchiveKind, ArchivePlatform, Link};
use crate::platform::Host;
use crate::progress::Spinner;
use crate::{Context, links, release};

mod extract;
mod source;

pub use extract::extract_file;
use extract::repair_executable_permissions;
pub(crate) use source::{render_links, resolve_source};

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
    #[error("unsafe archive path: {0}")]
    UnsafePath(PathBuf),
    #[error("unsupported platform")]
    UnsupportedPlatform,
    #[error("source required for archive platform")]
    MissingSource,
    #[error("archive kind required for archive platform")]
    MissingKind,
    #[error("version index did not contain a release")]
    EmptyVersionIndex,
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
    let kind = action
        .platform_kind(platform)
        .ok_or(ArchiveError::MissingKind)?;
    let strip_components = action.platform_strip_components(platform);
    let resolved = resolve_source(source, &platform.platform)?;

    let install_dir = links::install_dir(ctx, tool, &resolved.version);
    let install_dir_text = install_dir.to_string_lossy();
    let mut bindings = HashMap::new();
    bindings.insert("version", resolved.version.as_str());
    bindings.insert("platform", platform.platform.as_str());
    bindings.insert("install_dir", install_dir_text.as_ref());
    let rendered_links = render_links(action.platform_links(platform), &bindings)?;
    let rendered_app_links = render_links(action.platform_app_links(platform), &bindings)?;

    let temp_dir = install_dir.with_extension("tmp");
    fs::remove_dir_if_exists(&temp_dir)?;
    fs::remove_dir_if_exists(&install_dir)?;

    let download_dir = fs::tmp_dir("bootstrap-archive")?;
    let archive_path = download_dir.path().join(match kind {
        ArchiveKind::TarXz => "archive.tar.xz",
        ArchiveKind::TarGz => "archive.tar.gz",
        ArchiveKind::Zip => "archive.zip",
    });
    let client = Client::new("dotfiles-bootstrap")?;
    let progress = Spinner::new(format!("{tool}: downloading {}", resolved.version));
    client.download_file(&resolved.url, &archive_path)?;
    progress.set_message(format!("{tool}: extracting {}", resolved.version));

    extract_file(&archive_path, &temp_dir, kind, strip_components)?;
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
