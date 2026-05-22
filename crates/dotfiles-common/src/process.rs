use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};
use std::process::ExitStatus;

use thiserror::Error;

#[derive(Debug, Error)]
pub enum ProcessError {
    #[error("empty command")]
    EmptyCommand,
    #[error("failed to spawn {program}: {source}")]
    Spawn {
        program: String,
        #[source]
        source: std::io::Error,
    },
    #[error("command failed: {program}")]
    CommandFailed { program: String, status: ExitStatus },
}

#[derive(Debug)]
pub struct Output {
    pub status: ExitStatus,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
}

impl Output {
    #[inline]
    #[must_use]
    pub fn succeeded(&self) -> bool {
        self.status.success()
    }
}

#[must_use]
pub fn path_of(bin: &str) -> Option<PathBuf> {
    // Catalog commands sometimes provide an absolute or relative path instead
    // of a bare executable name; `which` intentionally handles only the latter.
    if is_path_like(bin) {
        let path = PathBuf::from(bin);
        return path.is_file().then_some(path);
    }
    which::which(bin).ok()
}

#[must_use]
pub fn path_in_dir(dir: &Path, bin: &str) -> Option<PathBuf> {
    executable_candidates(bin)
        .into_iter()
        .map(|name| dir.join(name))
        .find(|path| path.is_file())
}

/// Runs a command and requires a successful exit status.
///
/// # Errors
///
/// Returns an error if the command is empty, cannot be spawned, or exits unsuccessfully.
pub fn run(argv: &[String]) -> Result<(), ProcessError> {
    run_in_with_env(
        None::<&Path>,
        argv,
        std::iter::empty::<(OsString, OsString)>(),
    )
}

/// Runs a command with extra environment and requires a successful exit status.
///
/// # Errors
///
/// Returns an error if the command is empty, cannot be spawned, or exits unsuccessfully.
pub fn run_with_env<I, K, V>(argv: &[String], env: I) -> Result<(), ProcessError>
where
    I: IntoIterator<Item = (K, V)>,
    K: Into<OsString>,
    V: Into<OsString>,
{
    run_in_with_env(None::<&Path>, argv, env)
}

/// Runs a command in an optional working directory with extra environment and requires success.
///
/// # Errors
///
/// Returns an error if the command is empty, cannot be spawned, or exits unsuccessfully.
pub fn run_in_with_env<P, I, K, V>(
    cwd: Option<P>,
    argv: &[String],
    env: I,
) -> Result<(), ProcessError>
where
    P: AsRef<Path>,
    I: IntoIterator<Item = (K, V)>,
    K: Into<OsString>,
    V: Into<OsString>,
{
    let expr = expression(cwd, argv, env)?;
    let program = argv[0].clone();
    let status = expr
        .unchecked()
        .run()
        .map_err(|source| ProcessError::Spawn {
            program: program.clone(),
            source,
        })?
        .status;
    if status.success() {
        Ok(())
    } else {
        Err(ProcessError::CommandFailed { program, status })
    }
}

fn expression<P, I, K, V>(
    cwd: Option<P>,
    argv: &[String],
    env: I,
) -> Result<duct::Expression, ProcessError>
where
    P: AsRef<Path>,
    I: IntoIterator<Item = (K, V)>,
    K: Into<OsString>,
    V: Into<OsString>,
{
    let (program, arguments) = argv.split_first().ok_or(ProcessError::EmptyCommand)?;
    let env = env
        .into_iter()
        .map(|(name, value)| (name.into(), value.into()))
        .collect::<Vec<(OsString, OsString)>>();
    let resolved_program = resolve_with_env_path(program, &env).map_or_else(
        || program.clone(),
        |path| path.to_string_lossy().into_owned(),
    );
    let mut expr = duct::cmd(resolved_program, arguments);
    if let Some(cwd) = cwd {
        expr = expr.dir(cwd.as_ref());
    }
    for (name, value) in env {
        expr = expr.env(name, value);
    }
    Ok(expr)
}

fn resolve_with_env_path(program: &str, env: &[(OsString, OsString)]) -> Option<PathBuf> {
    if is_path_like(program) {
        return None;
    }

    let path = env
        .iter()
        .rev()
        .find_map(|(name, value)| (name == OsStr::new("PATH")).then_some(value))?;
    let executable = executable_name(program);
    std::env::split_paths(path).find_map(|dir| {
        let candidate = dir.join(&executable);
        candidate.is_file().then_some(candidate)
    })
}

/// Runs a command with extra environment and captures stdout and stderr.
///
/// # Errors
///
/// Returns an error if the command is empty or cannot be spawned.
pub fn capture_with_env<I, K, V>(argv: &[String], env: I) -> Result<Output, ProcessError>
where
    I: IntoIterator<Item = (K, V)>,
    K: Into<OsString>,
    V: Into<OsString>,
{
    let program = argv.first().cloned().ok_or(ProcessError::EmptyCommand)?;
    let output = expression(None::<&Path>, argv, env)?
        .stdout_capture()
        .stderr_capture()
        .unchecked()
        .run()
        .map_err(|source| ProcessError::Spawn { program, source })?;
    Ok(Output {
        status: output.status,
        stdout: output.stdout,
        stderr: output.stderr,
    })
}

/// Runs a command and returns trimmed stdout as text.
///
/// # Errors
///
/// Returns an error if the command cannot be captured or exits unsuccessfully.
pub fn trimmed_text(argv: &[String]) -> Result<String, ProcessError> {
    trimmed_text_with_env(argv, std::iter::empty::<(OsString, OsString)>())
}

/// Runs a command with extra environment and returns trimmed stdout as text.
///
/// # Errors
///
/// Returns an error if the command cannot be captured or exits unsuccessfully.
pub fn trimmed_text_with_env<I, K, V>(argv: &[String], env: I) -> Result<String, ProcessError>
where
    I: IntoIterator<Item = (K, V)>,
    K: Into<OsString>,
    V: Into<OsString>,
{
    let output = capture_with_env(argv, env)?;
    if !output.status.success() {
        return Err(ProcessError::CommandFailed {
            program: argv.first().cloned().unwrap_or_default(),
            status: output.status,
        });
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

fn is_path_like(value: &str) -> bool {
    let path = Path::new(value);
    path.is_absolute() || value.contains(std::path::MAIN_SEPARATOR) || value.contains('/')
}

/// Adds `.exe` on Windows when a catalog bin is declared without a suffix.
#[inline]
#[must_use]
pub fn executable_name(name: &str) -> String {
    match (cfg!(windows), Path::new(name).extension().is_none()) {
        (true, true) => format!("{name}.exe"),
        _ => name.to_owned(),
    }
}

/// Replaces argv[0] with a resolved path while preserving the caller's arguments.
#[inline]
#[must_use]
pub fn argv_with_resolved_program(argv_template: &[String], path: &Path) -> Vec<String> {
    let mut argv = argv_template.to_vec();
    if let Some(first) = argv.first_mut()
        && path
            .file_name()
            .and_then(|name| name.to_str())
            .is_some_and(|name| {
                *first == name || executable_stem(name).is_some_and(|stem| *first == stem)
            })
    {
        *first = path.to_string_lossy().into_owned();
    }
    argv
}

fn executable_stem(name: &str) -> Option<&str> {
    let (stem, extension) = name.rsplit_once('.')?;
    match extension.to_ascii_lowercase().as_str() {
        "bat" | "cmd" | "com" | "exe" => Some(stem),
        _ => None,
    }
}

fn executable_candidates(name: &str) -> Vec<String> {
    match (cfg!(windows), Path::new(name).extension().is_some()) {
        (true, false) => {}
        _ => return vec![name.to_owned()],
    }
    ["", ".exe", ".cmd", ".bat", ".com"]
        .into_iter()
        .map(|extension| format!("{name}{extension}"))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_windows_command_extensions() {
        let argv = vec!["npm".to_owned(), "--version".to_owned()];
        let resolved = argv_with_resolved_program(&argv, Path::new("/tools/npm.cmd"));
        assert_eq!(resolved[0], "/tools/npm.cmd");
        assert_eq!(resolved[1], "--version");
    }
}
