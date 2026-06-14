use std::env;
use std::io;
use std::process::{ExitCode, ExitStatus};

use lsp_diagnostic_filter::proxy_lsp_command;

fn main() -> ExitCode {
    match run() {
        Ok(status) => exit_code(status),
        Err(error) => {
            eprintln!("{error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> io::Result<ExitStatus> {
    let args = env::args().skip(1).collect::<Vec<_>>();
    if handle_static_args(&args) {
        return Ok(success_status());
    }

    let command_start = args
        .iter()
        .position(|arg| arg == "--")
        .map_or(0, |index| index + 1);
    let Some(program) = args.get(command_start) else {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "usage: lsp-diagnostic-filter [--] <language-server> [args...]",
        ));
    };

    proxy_lsp_command(program, &args[command_start + 1..])
}

fn handle_static_args(args: &[String]) -> bool {
    match args.first().map(String::as_str) {
        Some("--version" | "-V") => {
            println!("lsp-diagnostic-filter {}", env!("CARGO_PKG_VERSION"));
            true
        }
        Some("--help" | "-h") => {
            println!("lsp-diagnostic-filter {}", env!("CARGO_PKG_VERSION"));
            println!("usage: lsp-diagnostic-filter [--] <language-server> [args...]");
            println!("Proxy an stdio LSP server while filtering template diagnostics.");
            true
        }
        _ => false,
    }
}

#[cfg(unix)]
fn success_status() -> ExitStatus {
    use std::os::unix::process::ExitStatusExt as _;
    ExitStatus::from_raw(0)
}

#[cfg(windows)]
fn success_status() -> ExitStatus {
    use std::os::windows::process::ExitStatusExt as _;
    ExitStatus::from_raw(0)
}

fn exit_code(status: ExitStatus) -> ExitCode {
    status
        .code()
        .and_then(|code| u8::try_from(code).ok())
        .map_or(ExitCode::FAILURE, ExitCode::from)
}
