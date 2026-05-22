use std::path::PathBuf;

use directories::BaseDirs;

use crate::error::{Error, Result};

#[derive(Debug)]
pub struct Context {
    pub home_dir: PathBuf,
    pub source_dir: PathBuf,
    pub os: Os,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Os {
    Darwin,
    Linux,
    Windows,
    Other(String),
}

#[derive(Debug, Default)]
pub struct Options {
    pub home_dir: Option<PathBuf>,
    pub source_dir: Option<PathBuf>,
    pub os: Option<String>,
}

pub fn context_with_options(options: &Options) -> Result<Context> {
    let base_dirs = BaseDirs::new().ok_or(Error::MissingEnv("HOME"))?;
    let home = base_dirs.home_dir().to_path_buf();
    let home_dir = options
        .home_dir
        .clone()
        .or_else(|| env_path("CHEZMOI_HOME_DIR"))
        .unwrap_or(home);
    let source_dir = options
        .source_dir
        .clone()
        .or_else(|| env_path("CHEZMOI_SOURCE_DIR"))
        .map(Ok)
        .unwrap_or_else(infer_source_dir)?;
    let os = Os::from_name(
        &options
            .os
            .clone()
            .or_else(|| {
                std::env::var("CHEZMOI_OS")
                    .ok()
                    .filter(|value| !value.trim().is_empty())
            })
            .unwrap_or_else(host_os_name),
    );
    Ok(Context {
        home_dir,
        source_dir,
        os,
    })
}

fn env_path(name: &'static str) -> Option<PathBuf> {
    std::env::var_os(name)
        .map(PathBuf::from)
        .filter(|path| !path.as_os_str().is_empty())
}

fn infer_source_dir() -> Result<PathBuf> {
    let current_dir = std::env::current_dir()?;
    infer_source_dir_from(current_dir.clone()).ok_or(Error::SourceDirNotFound(current_dir))
}

fn infer_source_dir_from(start: PathBuf) -> Option<PathBuf> {
    for ancestor in start.ancestors() {
        if is_chezmoi_source_dir(ancestor) {
            return Some(ancestor.to_path_buf());
        }

        let dotfiles = ancestor.join("dotfiles");
        if is_chezmoi_source_dir(&dotfiles) {
            return Some(dotfiles);
        }
    }
    None
}

fn is_chezmoi_source_dir(path: &std::path::Path) -> bool {
    path.join(".chezmoiignore").is_file()
        || path.join(".chezmoiexternal.toml").is_file()
        || path.join(".chezmoiexternal.toml.tmpl").is_file()
        || path.join(".chezmoiscripts").is_dir()
}

fn host_os_name() -> String {
    if cfg!(target_os = "macos") {
        "darwin".to_owned()
    } else if cfg!(target_os = "linux") {
        "linux".to_owned()
    } else if cfg!(windows) {
        "windows".to_owned()
    } else {
        std::env::consts::OS.to_owned()
    }
}

impl Os {
    fn from_name(name: &str) -> Self {
        match name {
            "darwin" | "macos" => Self::Darwin,
            "linux" => Self::Linux,
            "windows" => Self::Windows,
            other => Self::Other(other.to_owned()),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn infers_source_dir_from_repo_root() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let dotfiles = temp.path().join("dotfiles");
        fs_err::create_dir_all(&dotfiles)?;
        fs_err::write(dotfiles.join(".chezmoiignore"), "")?;

        let inferred = infer_source_dir_from(temp.path().to_path_buf())
            .ok_or_else(|| Error::CommandFailed("source dir not inferred".into()))?;

        assert_eq!(inferred, dotfiles);
        Ok(())
    }

    #[test]
    fn infers_source_dir_from_inside_source_dir() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let dotfiles = temp.path().join("dotfiles");
        let nested = dotfiles.join("dot_config/raycast");
        fs_err::create_dir_all(&nested)?;
        fs_err::write(dotfiles.join(".chezmoiignore"), "")?;

        let inferred = infer_source_dir_from(nested)
            .ok_or_else(|| Error::CommandFailed("source dir not inferred".into()))?;

        assert_eq!(inferred, dotfiles);
        Ok(())
    }
}
