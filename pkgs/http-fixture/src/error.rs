use std::net::AddrParseError;
use std::path::PathBuf;

use thiserror::Error as ThisError;

#[derive(Debug, ThisError)]
pub(crate) enum Error {
    #[error("failed to bind HTTP server at {addr}: {source}")]
    Bind {
        addr: std::net::SocketAddr,
        source: Box<dyn std::error::Error + Send + Sync>,
    },
    #[error("--tls-cert and --tls-key must be provided together")]
    IncompleteTlsConfig,
    #[error("failed to read config at {path}")]
    ReadConfig {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("failed to parse config at {path}: {source}")]
    ParseConfig {
        path: PathBuf,
        source: toml::de::Error,
    },
    #[error("failed to read TLS certificate at {path}")]
    ReadTlsCert {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("failed to read TLS private key at {path}")]
    ReadTlsKey {
        path: PathBuf,
        source: std::io::Error,
    },
    #[error("route {index} must set exactly one of path, path_prefix, or path_suffix")]
    InvalidRouteMatcher { index: usize },
    #[error("route {index} must set at most one of body, body_html, or body_json")]
    InvalidRouteBody { index: usize },
    #[error("failed to parse header {name}")]
    Header { name: String },
    #[error("failed to serialize JSON response")]
    Json(#[from] serde_json::Error),
    #[error("failed to parse socket address")]
    AddrParse(#[from] AddrParseError),
}

pub(crate) type Result<T> = std::result::Result<T, Error>;
