use std::process::ExitStatus;

use crate::Result;

/// Exits the process using the result from a command runner.
///
/// # Panics
///
/// Never panics.
pub fn exit_with_result(result: Result<i32>) -> ! {
    match result {
        Ok(code) => std::process::exit(code),
        Err(err) => {
            eprintln!("error: {err}");
            std::process::exit(1);
        }
    }
}

/// Runs a command inheriting stdio and returns its normalized exit code.
///
/// # Errors
///
/// Returns an error if spawning or waiting for the command fails.
pub fn run_inherit(command: &duct::Expression) -> Result<i32> {
    let output = command.unchecked().run()?;
    Ok(exit_code(output.status))
}

pub fn run_silent(program: &str, args: &[&str]) {
    let _ = duct::cmd(program, args)
        .stdin_null()
        .stdout_null()
        .stderr_null()
        .unchecked()
        .run();
}

#[must_use]
pub fn exit_code(status: ExitStatus) -> i32 {
    status.code().unwrap_or_else(|| {
        #[cfg(unix)]
        {
            use std::os::unix::process::ExitStatusExt;
            status.signal().map_or(1, |sig| (128 + sig).min(255))
        }
        #[cfg(not(unix))]
        {
            1
        }
    })
}
