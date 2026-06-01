use zellij_theme_tools::{Result, detect_theme, home_dir, run_inherit, sanitize_session_name};

fn main() {
    match run() {
        Ok(code) => std::process::exit(code),
        Err(err) => {
            eprintln!("error: {err}");
            std::process::exit(1);
        }
    }
}

fn run() -> Result<i32> {
    if wants_version() {
        println!("zellij-auto-theme {}", env!("CARGO_PKG_VERSION"));
        return Ok(0);
    }

    let selected = detect_theme();
    let uid = std::env::var("UID")
        .ok()
        .filter(|value| !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit()));
    #[cfg(unix)]
    let uid = uid.unwrap_or_else(|| {
        duct::cmd("id", ["-u"])
            .stdout_capture()
            .stderr_null()
            .unchecked()
            .run()
            .ok()
            .filter(|output| output.status.success())
            .map(|output| String::from_utf8_lossy(&output.stdout).trim().to_owned())
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| "0".to_owned())
    });
    #[cfg(not(unix))]
    let uid = uid.unwrap_or_else(|| "0".to_owned());
    let socket_dir = std::env::temp_dir().join(format!("zellij-{uid}"));
    fs_err::create_dir_all(&socket_dir)?;

    let session_name = default_session_name()?;
    let command = duct::cmd(
        "zellij",
        [
            "options",
            "--theme",
            selected.name,
            "--default-layout",
            "compact",
            "--attach-to-session",
            "true",
            "--on-force-close",
            "quit",
            "--session-name",
            session_name.as_str(),
        ],
    )
    .env("ZELLIJ_DEFAULT_FG", selected.colors.fg)
    .env("ZELLIJ_DEFAULT_BG", selected.colors.bg)
    .env("ZELLIJ_SOCKET_DIR", socket_dir);
    run_inherit(&command)
}

fn wants_version() -> bool {
    std::env::args_os()
        .skip(1)
        .any(|arg| arg == "--version" || arg == "-V")
}

fn default_session_name() -> Result<String> {
    let cwd = std::env::current_dir()?;
    let home = home_dir()?;
    let raw = if cwd == home {
        std::env::var("USER").unwrap_or_else(|_| "session".to_owned())
    } else {
        cwd.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("session")
            .to_owned()
    };
    let sanitized = sanitize_session_name(raw.trim());
    Ok(if sanitized.is_empty() {
        "session".to_owned()
    } else {
        sanitized
    })
}
