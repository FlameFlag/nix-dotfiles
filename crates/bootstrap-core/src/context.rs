use std::ffi::OsString;
use std::path::{Path, PathBuf};

use directories::BaseDirs;
use fs_err as fs;

#[derive(Debug, Clone)]
pub struct Context {
    pub repo_dir: PathBuf,
    pub home: PathBuf,
    pub bin_dir: PathBuf,
    pub opt_dir: PathBuf,
    pub isolated_home: bool,
}

impl Context {
    /// Creates a bootstrap context rooted at `repo_dir`.
    ///
    /// # Errors
    ///
    /// Returns an error if the user's base directories cannot be determined.
    pub fn new(repo_dir: impl Into<PathBuf>) -> std::io::Result<Self> {
        Self::new_with_home(
            repo_dir,
            std::env::var_os("BOOTSTRAP_HOME").map(PathBuf::from),
        )
    }

    pub fn new_with_home(
        repo_dir: impl Into<PathBuf>,
        home: Option<PathBuf>,
    ) -> std::io::Result<Self> {
        let base_dirs = BaseDirs::new().ok_or_else(|| {
            std::io::Error::new(std::io::ErrorKind::NotFound, "home directory must be set")
        })?;
        let home_overridden = home.is_some();
        let home = home.unwrap_or_else(|| base_dirs.home_dir().to_path_buf());
        let bin_dir = if home_overridden {
            home.join(".local").join("bin")
        } else {
            base_dirs.executable_dir().map_or_else(
                || home.join(".local").join("bin"),
                std::path::Path::to_path_buf,
            )
        };
        let opt_dir = home.join(".local").join("opt");
        let cargo_bin_dir = home.join(".cargo").join("bin");
        validate_path_entries([bin_dir.as_path(), cargo_bin_dir.as_path()])?;
        fs::create_dir_all(&bin_dir)?;
        fs::create_dir_all(&opt_dir)?;
        Ok(Self {
            repo_dir: repo_dir.into(),
            home,
            bin_dir,
            opt_dir,
            isolated_home: home_overridden,
        })
    }

    pub fn catalog_path(&self) -> PathBuf {
        std::env::var_os("BOOTSTRAP_TOOLS_CATALOG").map_or_else(
            || self.repo_dir.join("bootstrap").join("tools.toml"),
            PathBuf::from,
        )
    }

    #[must_use]
    pub fn command_env(&self) -> Vec<(OsString, OsString)> {
        let mut env = Vec::new();
        let cargo_home = self.env_or_path("CARGO_HOME", self.home.join(".cargo"));
        let cargo_target_dir = self.env_or_path(
            "CARGO_TARGET_DIR",
            self.home.join(".cache").join("bootstrap").join("target"),
        );
        let rustup_home = self.env_or_path("RUSTUP_HOME", self.home.join(".rustup"));
        let uv_tool_dir = self.opt_dir.join("uv-tools");
        let _ = fs::create_dir_all(&self.bin_dir);
        let _ = fs::create_dir_all(&cargo_home);
        let _ = fs::create_dir_all(&cargo_target_dir);
        let _ = fs::create_dir_all(&rustup_home);
        let _ = fs::create_dir_all(&uv_tool_dir);

        if let Some(path) = bootstrap_path(&[self.bin_dir.clone(), cargo_home.join("bin")]) {
            env.push((OsString::from("PATH"), path));
        }

        env.push((OsString::from("CARGO_HOME"), cargo_home.into_os_string()));
        env.push((
            OsString::from("CARGO_TARGET_DIR"),
            cargo_target_dir.into_os_string(),
        ));
        env.push((OsString::from("RUSTUP_HOME"), rustup_home.into_os_string()));
        env.push((
            OsString::from("UV_TOOL_BIN_DIR"),
            self.bin_dir.clone().into_os_string(),
        ));
        env.push((OsString::from("UV_TOOL_DIR"), uv_tool_dir.into_os_string()));

        if self.isolated_home {
            env.extend(self.home_env());
        }

        env
    }

    fn home_env(&self) -> Vec<(OsString, OsString)> {
        let config = self.home.join(".config");
        let cache = self.home.join(".cache");
        let tmp = self.home.join(".cache").join("tmp");
        let appdata = self.home.join("AppData").join("Roaming");
        let local_appdata = self.home.join("AppData").join("Local");
        let _ = fs::create_dir_all(&tmp);
        isolated_home_env(
            &self.home,
            &config,
            &cache,
            &tmp,
            Some(WindowsHomeEnv {
                profile: &self.home,
                appdata: &appdata,
                local_appdata: &local_appdata,
            }),
            false,
        )
    }
}

#[cfg_attr(not(windows), allow(dead_code))]
pub(crate) struct WindowsHomeEnv<'a> {
    pub(crate) profile: &'a Path,
    pub(crate) appdata: &'a Path,
    pub(crate) local_appdata: &'a Path,
}

pub(crate) fn create_isolated_home_env(
    home: &Path,
    config: &Path,
    cache: &Path,
    tmp: &Path,
    windows: Option<WindowsHomeEnv<'_>>,
    git_config_nosystem: bool,
) -> std::io::Result<Vec<(OsString, OsString)>> {
    fs::create_dir_all(config)?;
    fs::create_dir_all(cache)?;
    fs::create_dir_all(tmp)?;

    #[cfg(windows)]
    if let Some(windows) = &windows {
        fs::create_dir_all(windows.profile)?;
        fs::create_dir_all(windows.appdata)?;
        fs::create_dir_all(windows.local_appdata)?;
    }

    Ok(isolated_home_env(
        home,
        config,
        cache,
        tmp,
        windows,
        git_config_nosystem,
    ))
}

pub(crate) fn isolated_home_env(
    home: &Path,
    config: &Path,
    cache: &Path,
    tmp: &Path,
    windows: Option<WindowsHomeEnv<'_>>,
    git_config_nosystem: bool,
) -> Vec<(OsString, OsString)> {
    let mut env = vec![
        (OsString::from("HOME"), home.to_path_buf().into_os_string()),
        (
            OsString::from("XDG_CONFIG_HOME"),
            config.to_path_buf().into_os_string(),
        ),
        (
            OsString::from("XDG_CACHE_HOME"),
            cache.to_path_buf().into_os_string(),
        ),
        (OsString::from("TMPDIR"), tmp.to_path_buf().into_os_string()),
        (OsString::from("TMP"), tmp.to_path_buf().into_os_string()),
        (OsString::from("TEMP"), tmp.to_path_buf().into_os_string()),
    ];

    if git_config_nosystem {
        env.push((OsString::from("GIT_CONFIG_NOSYSTEM"), OsString::from("1")));
    }

    #[cfg(windows)]
    if let Some(windows) = windows {
        if let Some(prefix) = windows.profile.components().next() {
            env.push((
                OsString::from("HOMEDRIVE"),
                PathBuf::from(prefix.as_os_str()).into_os_string(),
            ));
        }
        env.push((
            OsString::from("USERPROFILE"),
            windows.profile.to_path_buf().into_os_string(),
        ));
        env.push((
            OsString::from("APPDATA"),
            windows.appdata.to_path_buf().into_os_string(),
        ));
        env.push((
            OsString::from("LOCALAPPDATA"),
            windows.local_appdata.to_path_buf().into_os_string(),
        ));
    }
    #[cfg(not(windows))]
    let _ = windows;

    env
}

fn bootstrap_path(prefixes: &[PathBuf]) -> Option<OsString> {
    let mut entries = prefixes.to_vec();
    entries.extend(
        std::env::var_os("PATH")
            .into_iter()
            .flat_map(|path| std::env::split_paths(&path).collect::<Vec<_>>()),
    );
    std::env::join_paths(entries).ok()
}

fn validate_path_entries<'a>(
    entries: impl IntoIterator<Item = &'a std::path::Path>,
) -> std::io::Result<()> {
    std::env::join_paths(entries).map(|_| ()).map_err(|err| {
        std::io::Error::new(
            std::io::ErrorKind::InvalidInput,
            format!("bootstrap path cannot be represented in PATH: {err}"),
        )
    })
}

impl Context {
    fn env_or_path(&self, name: &str, fallback: PathBuf) -> PathBuf {
        if self.isolated_home {
            fallback
        } else {
            std::env::var_os(name)
                .map(PathBuf::from)
                .filter(|path| validate_path_entries([path.as_path()]).is_ok())
                .unwrap_or(fallback)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn rejects_isolated_home_that_cannot_be_represented_on_path() {
        let temp = tempfile::tempdir().expect("tempdir");
        let err = Context::new_with_home(
            temp.path().join("repo"),
            Some(temp.path().join("home:with-colon")),
        )
        .expect_err("colon home should be invalid on Unix PATH");

        assert_eq!(err.kind(), std::io::ErrorKind::InvalidInput);
    }
}
