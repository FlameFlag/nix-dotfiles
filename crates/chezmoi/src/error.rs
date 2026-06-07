use thiserror::Error;

#[derive(Debug, Error, miette::Diagnostic)]
pub enum Error {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error(transparent)]
    Http(#[from] dotfiles_common::http::HttpError),
    #[error(transparent)]
    Process(#[from] dotfiles_common::process::ProcessError),
    #[error(transparent)]
    Toml(#[from] toml::de::Error),
    #[error("environment variable {0} is required")]
    #[diagnostic(help("set the variable in the environment before running this helper"))]
    MissingEnv(&'static str),
    #[error(
        "could not find chezmoi source dir from {0}; pass --source-dir DIR or run from this repo"
    )]
    #[diagnostic(help("pass --source-dir DIR or run the command from inside this dotfiles repo"))]
    SourceDirNotFound(std::path::PathBuf),
    #[error("command failed: {0}")]
    CommandFailed(String),
}

pub type Result<T> = std::result::Result<T, Error>;
