use std::time::Duration;

use process_wrap::tokio::{CommandWrap, ProcessGroup};
use tokio::io::{AsyncRead, AsyncReadExt};
use tokio::process::Command;
use tokio::time::timeout;
use tokio_util::sync::CancellationToken;

const KILL_GRACE: Duration = Duration::from_secs(5);
const OUTPUT_LIMIT: usize = 1024 * 1024;

#[derive(Debug)]
pub(crate) struct CommandOutput {
    pub(crate) exit_status: String,
    pub(crate) success: bool,
    pub(crate) timed_out: bool,
    pub(crate) stdout: CapturedOutput,
    pub(crate) stderr: CapturedOutput,
}

#[derive(Debug)]
pub(crate) struct CapturedOutput {
    pub(crate) bytes: Vec<u8>,
    pub(crate) truncated: bool,
}

pub(crate) async fn run_with_timeout(
    process: Command,
    command_timeout: Duration,
    cancellation_token: CancellationToken,
) -> Result<CommandOutput, std::io::Error> {
    let mut process = CommandWrap::from(process);
    process.wrap(ProcessGroup::leader());
    let mut child = process.spawn()?;
    let stdout = child.stdout().take();
    let stderr = child.stderr().take();
    let stdout_task = tokio::spawn(read_limited(stdout));
    let stderr_task = tokio::spawn(read_limited(stderr));

    let (exit_status, success, timed_out) = tokio::select! {
        status = child.wait() => {
            let status = status?;
            let exit_status = status.code().map_or_else(
                || "terminated by signal".to_owned(),
                |code| code.to_string(),
            );
            (exit_status, status.success(), false)
        }
        _ = tokio::time::sleep(command_timeout) => {
            terminate_child(child.as_mut()).await;
            (
                format!("timed out after {} seconds", command_timeout.as_secs()),
                false,
                true,
            )
        }
        _ = cancellation_token.cancelled() => {
            terminate_child(child.as_mut()).await;
            ("cancelled".to_owned(), false, false)
        }
    };

    let (stdout, stderr) = tokio::join!(stdout_task, stderr_task);
    Ok(CommandOutput {
        exit_status,
        success,
        timed_out,
        stdout: stdout.map_err(std::io::Error::other)??,
        stderr: stderr.map_err(std::io::Error::other)??,
    })
}

async fn terminate_child(child: &mut dyn process_wrap::tokio::ChildWrapper) {
    #[cfg(unix)]
    {
        let _ = child.signal(15);
    }
    if timeout(KILL_GRACE, child.wait()).await.is_err() {
        let _ = child.start_kill();
        let _ = timeout(KILL_GRACE, child.wait()).await;
    }
}

async fn read_limited<R>(reader: Option<R>) -> Result<CapturedOutput, std::io::Error>
where
    R: AsyncRead + Unpin,
{
    let Some(mut reader) = reader else {
        return Ok(CapturedOutput {
            bytes: Vec::new(),
            truncated: false,
        });
    };

    let mut bytes = Vec::new();
    let mut chunk = [0; 8192];
    let mut truncated = false;
    loop {
        let read = reader.read(&mut chunk).await?;
        if read == 0 {
            break;
        }
        if bytes.len() < OUTPUT_LIMIT {
            let remaining = OUTPUT_LIMIT - bytes.len();
            truncated |= read > remaining;
            bytes.extend_from_slice(&chunk[..read.min(remaining)]);
        } else {
            truncated = true;
        }
    }

    Ok(CapturedOutput { bytes, truncated })
}

#[cfg(test)]
mod tests {
    use std::io::Cursor;

    use super::*;

    #[tokio::test]
    async fn read_limited_caps_captured_bytes() -> Result<(), std::io::Error> {
        let input = vec![b'a'; OUTPUT_LIMIT + 1];
        let captured = read_limited(Some(Cursor::new(input))).await?;

        assert_eq!(captured.bytes.len(), OUTPUT_LIMIT);
        assert!(captured.truncated);
        Ok(())
    }

    #[tokio::test]
    async fn run_with_timeout_honors_cancellation_token() -> Result<(), std::io::Error> {
        let mut command = Command::new("/bin/sh");
        command.args(["-c", "sleep 10"]);
        let cancellation_token = CancellationToken::new();
        let cancel = cancellation_token.clone();

        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_millis(50)).await;
            cancel.cancel();
        });

        let started = std::time::Instant::now();
        let output = run_with_timeout(command, Duration::from_secs(10), cancellation_token).await?;

        assert_eq!(output.exit_status, "cancelled");
        assert!(!output.success);
        assert!(!output.timed_out);
        assert!(started.elapsed() < Duration::from_secs(2));
        Ok(())
    }
}
