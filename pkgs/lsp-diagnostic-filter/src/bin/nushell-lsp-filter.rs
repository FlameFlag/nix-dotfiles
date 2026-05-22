use std::env;
use std::io::{self, Read};
use std::process::{Command, ExitCode, ExitStatus, Stdio};
use std::thread;

use lsp_diagnostic_filter::LspFilter;

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
    let real_nu = env::var("NU_LSP_REAL_NU").unwrap_or_else(|_| "nu".to_owned());
    let args = env::args().skip(1).collect::<Vec<_>>();

    if !args.iter().any(|arg| arg == "--lsp") {
        return Command::new(real_nu).args(args).status();
    }

    proxy_lsp(&real_nu, &args)
}

fn proxy_lsp(real_nu: &str, args: &[String]) -> io::Result<ExitStatus> {
    let mut child = Command::new(real_nu)
        .args(args)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()?;

    let mut child_stdin = child
        .stdin
        .take()
        .ok_or_else(|| io::Error::other("child stdin was not piped"))?;
    let stdin_thread = thread::spawn(move || {
        let mut stdin = io::stdin().lock();
        io::copy(&mut stdin, &mut child_stdin)
    });

    let mut child_stderr = child
        .stderr
        .take()
        .ok_or_else(|| io::Error::other("child stderr was not piped"))?;
    let stderr_thread = thread::spawn(move || {
        let mut stderr = io::stderr().lock();
        io::copy(&mut child_stderr, &mut stderr)
    });

    let mut child_stdout = child
        .stdout
        .take()
        .ok_or_else(|| io::Error::other("child stdout was not piped"))?;
    filter_stdout(&mut child_stdout)?;

    let status = child.wait()?;
    join_io_thread(stdin_thread)?;
    join_io_thread(stderr_thread)?;

    Ok(status)
}

fn filter_stdout(stdout: &mut impl Read) -> io::Result<()> {
    let mut filter = LspFilter::new();
    let mut output = io::stdout().lock();
    let mut chunk = [0_u8; 8192];

    loop {
        let read = stdout.read(&mut chunk)?;
        if read == 0 {
            return Ok(());
        }
        filter.accept(&chunk[..read], &mut output)?;
    }
}

fn join_io_thread(handle: thread::JoinHandle<io::Result<u64>>) -> io::Result<()> {
    match handle.join() {
        Ok(Ok(_)) => Ok(()),
        Ok(Err(error)) if error.kind() == io::ErrorKind::BrokenPipe => Ok(()),
        Ok(Err(error)) => Err(error),
        Err(_) => Err(io::Error::other("I/O thread panicked")),
    }
}

fn exit_code(status: ExitStatus) -> ExitCode {
    status
        .code()
        .and_then(|code| u8::try_from(code).ok())
        .map_or(ExitCode::FAILURE, ExitCode::from)
}
