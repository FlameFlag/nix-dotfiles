use std::path::PathBuf;
use std::process::Stdio;
use std::time::Duration;

use rmcp::{ErrorData, handler::server::wrapper::Json, schemars};
use tokio::process::Command;
use tokio_util::sync::CancellationToken;

use crate::output::SystemRunOutput;
use crate::path_probe::user_shell_path;
use crate::process::run_with_timeout;

const DEFAULT_TIMEOUT: Duration = Duration::from_secs(300);
const MAX_TIMEOUT: Duration = Duration::from_secs(1_800);

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(deny_unknown_fields)]
pub(crate) struct SystemRunParams {
    #[schemars(description = "Shell command to execute through the system runner.")]
    command: String,
    #[schemars(description = "Optional working directory for the command.")]
    cwd: Option<String>,
    #[schemars(description = "Optional timeout in seconds. Defaults to 300; maximum is 1800.")]
    timeout_sec: Option<u64>,
}

pub(crate) async fn run_system_command(
    params: SystemRunParams,
    cancellation_token: CancellationToken,
) -> Result<Json<SystemRunOutput>, ErrorData> {
    if params.command.trim().is_empty() {
        return Err(ErrorData::invalid_params("command must not be empty", None));
    }
    let command_timeout = match command_timeout(params.timeout_sec) {
        Ok(timeout) => timeout,
        Err(message) => return Err(ErrorData::invalid_params(message, None)),
    };

    let Ok(runner) = system_runner_path() else {
        return Err(ErrorData::internal_error(
            "failed to locate sibling command runner binary",
            None,
        ));
    };
    let shell_path = user_shell_path().await;

    let mut process = Command::new("sudo");
    process.arg("-n").arg(runner);
    if let Some(path) = shell_path {
        process.args(["--env", &format!("PATH={path}")]);
    }
    process
        .arg("--")
        .args(["/bin/sh", "-c", &params.command])
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    if let Some(cwd) = params.cwd
        && !cwd.trim().is_empty()
    {
        process.current_dir(cwd);
    }

    match run_with_timeout(process, command_timeout, cancellation_token).await {
        Ok(output) => Ok(Json(output.into())),
        Err(err) => Err(ErrorData::internal_error(
            format!("failed to run command: {err}"),
            None,
        )),
    }
}

fn command_timeout(timeout_sec: Option<u64>) -> Result<Duration, String> {
    let Some(timeout_sec) = timeout_sec else {
        return Ok(DEFAULT_TIMEOUT);
    };
    if timeout_sec == 0 {
        return Err("timeout_sec must be greater than zero".to_owned());
    }
    let requested = Duration::from_secs(timeout_sec);
    if requested > MAX_TIMEOUT {
        return Err(format!(
            "timeout_sec must not exceed {} seconds",
            MAX_TIMEOUT.as_secs()
        ));
    }
    Ok(requested)
}

fn system_runner_path() -> Result<PathBuf, std::io::Error> {
    let mut path = std::env::current_exe()?;
    path.set_file_name("system-runner");
    Ok(path)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn command_timeout_defaults_and_validates_bounds() {
        assert_eq!(command_timeout(None), Ok(DEFAULT_TIMEOUT));
        assert_eq!(command_timeout(Some(1)), Ok(Duration::from_secs(1)));
        assert!(command_timeout(Some(0)).is_err());
        assert!(command_timeout(Some(MAX_TIMEOUT.as_secs() + 1)).is_err());
    }
}
