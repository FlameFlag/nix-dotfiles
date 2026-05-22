use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Http(#[from] dotfiles_common::http::HttpError),
    #[error(transparent)]
    Json(#[from] serde_json::Error),
    #[error(transparent)]
    Toml(#[from] toml::de::Error),
    #[error("environment variable {0} is required")]
    MissingEnv(&'static str),
    #[error(
        "could not find chezmoi source dir from {0}; pass --source-dir DIR or run from this repo"
    )]
    SourceDirNotFound(std::path::PathBuf),
    #[error("command failed: {0}")]
    CommandFailed(String),
}

pub type Result<T> = std::result::Result<T, Error>;
