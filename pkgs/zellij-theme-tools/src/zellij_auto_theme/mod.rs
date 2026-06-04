mod session;

use crate::{Result, detect_theme, run_inherit, wants_version_arg};

/// Runs `zellij-auto-theme`.
///
/// # Errors
///
/// Returns an error if the socket directory cannot be created, session naming
/// fails, or Zellij cannot be executed.
pub fn run() -> Result<i32> {
    if wants_version_arg() {
        println!("zellij-auto-theme {}", env!("CARGO_PKG_VERSION"));
        return Ok(0);
    }

    let selected = detect_theme();
    let socket_dir = std::env::temp_dir().join(format!("zellij-{}", session::current_uid()));
    fs_err::create_dir_all(&socket_dir)?;

    let session_name = session::default_session_name()?;
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
