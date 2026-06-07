use rmcp::schemars;
use serde::Serialize;

use crate::process::CommandOutput;

#[derive(Debug, Serialize, schemars::JsonSchema)]
pub(crate) struct SystemRunOutput {
    exit_status: String,
    success: bool,
    timed_out: bool,
    stdout: String,
    stderr: String,
    stdout_truncated: bool,
    stderr_truncated: bool,
}

impl From<CommandOutput> for SystemRunOutput {
    fn from(output: CommandOutput) -> Self {
        Self {
            exit_status: output.exit_status,
            success: output.success,
            timed_out: output.timed_out,
            stdout: String::from_utf8_lossy(&output.stdout.bytes).into_owned(),
            stderr: String::from_utf8_lossy(&output.stderr.bytes).into_owned(),
            stdout_truncated: output.stdout.truncated,
            stderr_truncated: output.stderr.truncated,
        }
    }
}
