use std::path::Path;

use crate::error::{Error, Result};
use dotfiles_common::fs::write_text_if_changed;
use dotfiles_common::process::{self, Output};

pub fn write_command_text_if_available(bin: &str, path: &Path, argv: &[String]) -> Result<bool> {
    if process::path_of(bin).is_none() {
        return Ok(false);
    }
    let text = command_text(argv)?;
    Ok(write_text_if_changed(path, &text)?)
}

pub fn command_text(argv: &[String]) -> Result<String> {
    let output = process::capture_with_env(argv, std::iter::empty::<(String, String)>())?;
    if !output.status.success() {
        return Err(Error::CommandFailed(command_label(argv)));
    }
    Ok(String::from_utf8_lossy(&output.stdout).into_owned())
}

pub fn command_output(argv: &[String]) -> Result<Output> {
    process::capture_with_env(argv, std::iter::empty::<(String, String)>()).map_err(Into::into)
}

pub fn command_output_with_stdin(argv: &[String], stdin: impl Into<Vec<u8>>) -> Result<Output> {
    process::capture_with_stdin(argv, stdin).map_err(Into::into)
}

pub fn run_command(argv: &[String]) -> Result<()> {
    process::run(argv).map_err(Into::into)
}

pub fn output_detail(output: &Output) -> String {
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_owned();
    if stderr.is_empty() {
        String::from_utf8_lossy(&output.stdout).trim().to_owned()
    } else {
        stderr
    }
}

pub fn warn_if_failed(name: &str, output: &Output) {
    if output.status.success() {
        return;
    }
    let message = output_detail(output);
    if message.is_empty() {
        eprintln!("warn: failed to generate {name} completions");
    } else {
        eprintln!("warn: failed to generate {name} completions: {message}");
    }
}

fn command_label(argv: &[String]) -> String {
    argv.first()
        .cloned()
        .unwrap_or_else(|| "<empty>".to_owned())
}
