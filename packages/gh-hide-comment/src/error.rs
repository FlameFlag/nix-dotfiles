use std::io;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum Error {
    #[error(transparent)]
    Http(#[from] dotfiles_common::http::HttpError),
    #[error(transparent)]
    Io(#[from] io::Error),
    #[error("missing GitHub token; set GH_TOKEN/GITHUB_TOKEN or run `gh auth login`")]
    MissingToken,
    #[error("gh auth token failed: {0}")]
    GhAuth(String),
    #[error("not a GitHub comment URL")]
    NotGithubUrl,
    #[error("missing comment anchor")]
    MissingCommentAnchor,
    #[error("invalid GitHub repository path")]
    InvalidRepoPath,
    #[error("invalid comment anchor")]
    InvalidCommentAnchor,
    #[error("GitHub API returned HTTP {status}: {body}")]
    GithubApi { status: u16, body: String },
    #[error("GitHub did not minimize the comment")]
    UnexpectedMinimizeResponse,
}

pub type Result<T> = std::result::Result<T, Error>;
