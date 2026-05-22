use std::ffi::OsString;
use std::path::PathBuf;

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
        let _ = fs::create_dir_all(&tmp);
        let mut env = vec![
            (OsString::from("HOME"), self.home.clone().into_os_string()),
            (OsString::from("XDG_CONFIG_HOME"), config.into_os_string()),
            (OsString::from("XDG_CACHE_HOME"), cache.into_os_string()),
            (OsString::from("TMPDIR"), tmp.clone().into_os_string()),
            (OsString::from("TMP"), tmp.clone().into_os_string()),
            (OsString::from("TEMP"), tmp.into_os_string()),
        ];

        if cfg!(windows) {
            let appdata = self.home.join("AppData").join("Roaming");
            let local_appdata = self.home.join("AppData").join("Local");
            if let Some(prefix) = self.home.components().next() {
                env.push((
                    OsString::from("HOMEDRIVE"),
                    PathBuf::from(prefix.as_os_str()).into_os_string(),
                ));
            }
            env.push((
                OsString::from("USERPROFILE"),
                self.home.clone().into_os_string(),
            ));
            env.push((OsString::from("APPDATA"), appdata.into_os_string()));
            env.push((
                OsString::from("LOCALAPPDATA"),
                local_appdata.into_os_string(),
            ));
        }

        env
    }
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

impl Context {
    fn env_or_path(&self, name: &str, fallback: PathBuf) -> PathBuf {
        if self.isolated_home {
            fallback
        } else {
            std::env::var_os(name).map_or(fallback, PathBuf::from)
        }
    }
}
