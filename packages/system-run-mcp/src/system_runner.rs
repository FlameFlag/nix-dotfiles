use std::ffi::{OsStr, OsString};
use std::fmt;
use std::os::unix::ffi::{OsStrExt, OsStringExt};
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use clap::{
    Parser,
    builder::{OsStringValueParser, TypedValueParser},
};

const DEFAULT_RUNNER_PATH: &str = "/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/sbin:/usr/local/bin:/opt/homebrew/sbin:/opt/homebrew/bin:/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/etc/profiles/per-user/root/bin";

fn main() {
    if handle_static_arg() {
        return;
    }

    let invocation =
        RunnerInvocation::parse(std::env::args_os().skip(1)).unwrap_or_else(|err| err.exit());

    let path = invocation.path();
    let mut command = if existing_non_executable_path(&invocation.program) {
        let mut command = Command::new("/bin/cat");
        command.arg(invocation.program);
        command
    } else {
        Command::new(resolve_program(&invocation.program, &path))
    };
    let err = command
        .env("PATH", path)
        .envs(invocation.env)
        .args(invocation.args)
        .exec();
    eprintln!("system-runner: {err}");
    std::process::exit(127);
}

fn handle_static_arg() -> bool {
    match std::env::args().nth(1).as_deref() {
        Some("--version" | "-V") => {
            println!("system-runner {}", env!("CARGO_PKG_VERSION"));
            true
        }
        _ => false,
    }
}

#[derive(Debug, Parser)]
#[command(name = "system-runner", no_binary_name = true)]
struct RunnerArgs {
    #[arg(
        long = "env",
        value_name = "KEY=VALUE",
        value_parser = OsStringValueParser::new().try_map(split_env_assignment)
    )]
    env: Vec<(OsString, OsString)>,
    #[arg(value_name = "COMMAND", required = true)]
    program: OsString,
    #[arg(
        value_name = "ARGS",
        trailing_var_arg = true,
        allow_hyphen_values = true
    )]
    args: Vec<OsString>,
}

struct RunnerInvocation {
    env: Vec<(OsString, OsString)>,
    program: OsString,
    args: Vec<OsString>,
}

impl RunnerInvocation {
    fn parse(args: impl IntoIterator<Item = OsString>) -> Result<Self, clap::Error> {
        let parsed = RunnerArgs::try_parse_from(args)?;
        Ok(Self {
            env: parsed.env,
            program: parsed.program,
            args: parsed.args,
        })
    }

    fn path(&self) -> OsString {
        self.env
            .iter()
            .find(|(key, _)| key == "PATH")
            .map(|(_, value)| value.clone())
            .unwrap_or_else(|| OsString::from(DEFAULT_RUNNER_PATH))
    }
}

#[derive(Debug)]
enum EnvAssignmentError {
    MissingEquals,
    EmptyName,
}

impl fmt::Display for EnvAssignmentError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MissingEquals => formatter.write_str("--env requires KEY=VALUE"),
            Self::EmptyName => formatter.write_str("--env variable name must not be empty"),
        }
    }
}

impl std::error::Error for EnvAssignmentError {}

fn split_env_assignment(assignment: OsString) -> Result<(OsString, OsString), EnvAssignmentError> {
    let bytes = assignment.as_os_str().as_bytes();
    let Some(index) = bytes.iter().position(|byte| *byte == b'=') else {
        return Err(EnvAssignmentError::MissingEquals);
    };
    if index == 0 {
        return Err(EnvAssignmentError::EmptyName);
    }
    Ok((
        OsString::from_vec(bytes[..index].to_vec()),
        OsString::from_vec(bytes[index + 1..].to_vec()),
    ))
}

fn existing_non_executable_path(program: &OsStr) -> bool {
    let path = Path::new(program);
    is_path_like(path) && path.is_file() && which::which(program).is_err()
}

fn resolve_program(program: &OsStr, path_env: &OsStr) -> OsString {
    let path = Path::new(program);
    if is_path_like(path) {
        return program.to_os_string();
    }
    which::which_in(program, Some(path_env), Path::new("."))
        .map(PathBuf::into_os_string)
        .unwrap_or_else(|_| program.to_os_string())
}

fn is_path_like(path: &Path) -> bool {
    path.components().count() != 1
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_accepts_env_before_program() -> Result<(), clap::Error> {
        let invocation = RunnerInvocation::parse([
            "--env".into(),
            "PATH=/custom/bin".into(),
            "--".into(),
            "sh".into(),
            "-c".into(),
            "true".into(),
        ])?;

        assert_eq!(invocation.path(), OsString::from("/custom/bin"));
        assert_eq!(invocation.program, OsString::from("sh"));
        assert_eq!(
            invocation.args,
            [OsString::from("-c"), OsString::from("true")]
        );
        Ok(())
    }

    #[test]
    fn parse_keeps_legacy_program_first_form() -> Result<(), clap::Error> {
        let invocation = RunnerInvocation::parse(["sh".into(), "-c".into(), "true".into()])?;

        assert_eq!(invocation.program, OsString::from("sh"));
        assert_eq!(
            invocation.args,
            [OsString::from("-c"), OsString::from("true")]
        );
        Ok(())
    }

    #[test]
    fn parse_keeps_program_arguments_that_look_like_options() -> Result<(), clap::Error> {
        let invocation = RunnerInvocation::parse([
            "env".into(),
            "--ignore-environment".into(),
            "PATH=/bin".into(),
        ])?;

        assert_eq!(invocation.program, OsString::from("env"));
        assert_eq!(
            invocation.args,
            [
                OsString::from("--ignore-environment"),
                OsString::from("PATH=/bin")
            ]
        );
        Ok(())
    }

    #[test]
    fn parse_missing_program_reports_clap_usage() {
        let result = RunnerInvocation::parse([]);
        assert!(result.is_err(), "missing program should fail");
        let Err(message) = result else {
            return;
        };
        let message = message.to_string();

        assert!(message.contains("Usage: system-runner"));
        assert!(message.contains("<COMMAND>"));
    }

    #[test]
    fn parse_env_requires_assignment() {
        assert!(split_env_assignment("PATH=/bin".into()).is_ok());
        assert!(split_env_assignment("PATH".into()).is_err());
        assert!(split_env_assignment("=value".into()).is_err());
    }

    #[test]
    fn parse_env_preserves_non_utf8_values() -> Result<(), EnvAssignmentError> {
        let assignment = OsString::from_vec(b"KEY=\xff".to_vec());
        let (key, value) = split_env_assignment(assignment)?;

        assert_eq!(key, OsString::from("KEY"));
        assert_eq!(value.as_os_str().as_bytes(), b"\xff");
        Ok(())
    }

    #[test]
    fn resolve_program_uses_supplied_path() -> Result<(), Box<dyn std::error::Error>> {
        let temp = tempfile::tempdir()?;
        let bin = temp.path().join("demo");
        std::fs::write(&bin, "#!/bin/sh\n")?;
        let mut permissions = std::fs::metadata(&bin)?.permissions();
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            permissions.set_mode(0o755);
            std::fs::set_permissions(&bin, permissions)?;
        }

        assert_eq!(
            resolve_program(OsStr::new("demo"), temp.path().as_os_str()),
            bin.into_os_string()
        );
        Ok(())
    }
}
