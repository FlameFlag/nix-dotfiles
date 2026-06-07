use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error("HOME is not set")]
    HomeMissing,
    #[error("codex executable not found")]
    CodexNotFound,
    #[error("btop executable not found")]
    BtopNotFound,
    #[error("helix executable not found")]
    HelixNotFound,
    #[error(transparent)]
    Toml(#[from] toml_edit::TomlError),
    #[error("invalid Codex config TOML shape")]
    InvalidCodexConfig,
}

pub type Result<T> = std::result::Result<T, Error>;
