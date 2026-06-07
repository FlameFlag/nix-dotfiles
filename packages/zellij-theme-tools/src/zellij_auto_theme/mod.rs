mod session;

use std::ffi::OsString;

use crate::{Result, run_inherit};

/// Runs the zellij profile for `zellij-theme-run`.
///
/// # Errors
///
/// Returns an error if the socket directory cannot be created, session naming
/// fails, or Zellij cannot be executed.
pub fn run_with_args(extra_args: Vec<OsString>) -> Result<i32> {
    let socket_dir = std::env::temp_dir().join(format!("zellij-{}", session::current_uid()));
    fs_err::create_dir_all(&socket_dir)?;

    let session_name = session::default_session_name()?;
    let mut args = vec![
        OsString::from("options"),
        OsString::from("--default-layout"),
        OsString::from("compact"),
        OsString::from("--attach-to-session"),
        OsString::from("true"),
        OsString::from("--on-force-close"),
        OsString::from("quit"),
        OsString::from("--session-name"),
        OsString::from(session_name),
    ];
    args.extend(extra_args);

    let command = duct::cmd("zellij", args).env("ZELLIJ_SOCKET_DIR", socket_dir);
    run_inherit(&command)
}
