mod session;

use std::ffi::OsString;

use crate::{Result, run_inherit};

/// Runs the zellij profile for `zellij-theme-run`.
///
/// # Errors
///
/// Returns an error if the socket directory cannot be created or Zellij cannot
/// be executed.
pub fn run_with_args(extra_args: Vec<OsString>) -> Result<i32> {
    let socket_dir = std::env::temp_dir().join(format!("zellij-{}", session::current_uid()));
    fs_err::create_dir_all(&socket_dir)?;

    let mut args = default_args();
    args.extend(extra_args);

    let command = duct::cmd("zellij", args).env("ZELLIJ_SOCKET_DIR", socket_dir);
    run_inherit(&command)
}

fn default_args() -> Vec<OsString> {
    vec![
        OsString::from("options"),
        OsString::from("--default-layout"),
        OsString::from("compact"),
        OsString::from("--attach-to-session"),
        OsString::from("false"),
        OsString::from("--mirror-session"),
        OsString::from("false"),
        OsString::from("--on-force-close"),
        OsString::from("quit"),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn ghostty_zellij_launches_fresh_session_by_default() {
        let args = default_args();

        assert!(
            args.windows(2)
                .any(|pair| pair == ["--attach-to-session", "false"])
        );
        assert!(
            args.windows(2)
                .any(|pair| pair == ["--mirror-session", "false"])
        );
        assert!(!args.contains(&OsString::from("--session-name")));
    }
}
