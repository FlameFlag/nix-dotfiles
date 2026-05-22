use std::path::Path;

use crate::error::{Error, Result};
use crate::fs::write_text_if_changed;

pub fn write_command_text_if_available(
    bin: &str,
    path: &Path,
    command: &duct::Expression,
) -> Result<bool> {
    if which::which(bin).is_err() {
        return Ok(false);
    }
    let text = command_text(command)?;
    write_text_if_changed(path, &text)
}

pub fn command_text(command: &duct::Expression) -> Result<String> {
    let output = command
        .stdout_capture()
        .stderr_capture()
        .unchecked()
        .run()?;
    if !output.status.success() {
        return Err(Error::CommandFailed(format!("{command:?}")));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

pub fn run_command(command: &duct::Expression) -> Result<()> {
    let output = command.unchecked().run()?;
    if output.status.success() {
        Ok(())
    } else {
        Err(Error::CommandFailed(format!("{command:?}")))
    }
}

pub fn warn_if_failed(name: &str, output: &std::process::Output) {
    if output.status.success() {
        return;
    }
    let message = String::from_utf8_lossy(&output.stderr);
    let message = message.trim();
    if message.is_empty() {
        eprintln!("warn: failed to generate {name} completions");
    } else {
        eprintln!("warn: failed to generate {name} completions: {message}");
    }
}
