use std::collections::HashMap;

use dotfiles_common::{fs, http::Client, template};
use thiserror::Error;

use crate::catalog::FileAction;
use crate::progress::Spinner;
use crate::{Context, archive, links};

#[derive(Debug, Error)]
pub enum FileError {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Http(#[from] dotfiles_common::http::HttpError),
    #[error(transparent)]
    Template(#[from] template::TemplateError),
    #[error(transparent)]
    Archive(#[from] archive::ArchiveError),
    #[error(transparent)]
    Link(#[from] links::LinkError),
}

/// Installs a standalone downloaded file under the managed opt tree.
///
/// # Errors
///
/// Returns an error if source resolution, download, permission repair, or linking fails.
pub fn install_file(ctx: &Context, tool: &str, action: &FileAction) -> Result<(), FileError> {
    let resolved = archive::resolve_source(&action.source, "")?;
    let install_dir = links::install_dir(ctx, tool, &resolved.version);
    fs::remove_dir_if_exists(&install_dir)?;
    fs_err::create_dir_all(&install_dir)?;

    let target = install_dir.join(&action.file);
    let client = Client::new("dotfiles-bootstrap")?;
    let progress = Spinner::new(format!("{tool}: downloading {}", resolved.version));
    client.download_file(&resolved.url, &target)?;
    progress.set_message(format!("{tool}: repairing executable permissions"));
    fs::make_executable(&target)?;

    let install_dir_text = install_dir.to_string_lossy();
    let mut bindings = HashMap::new();
    bindings.insert("version", resolved.version.as_str());
    bindings.insert("platform", "");
    bindings.insert("install_dir", install_dir_text.as_ref());
    let rendered_links = archive::render_links(&action.links, &bindings)?;
    progress.set_message(format!("{tool}: linking binaries"));
    links::link_many_adopt_existing(ctx, tool, &install_dir, &rendered_links)?;
    progress.finish_and_clear();
    Ok(())
}
