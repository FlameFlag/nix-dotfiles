use crate::{Result, home_dir, sanitize_session_name};

pub(super) fn current_uid() -> String {
    let uid = std::env::var("UID")
        .ok()
        .filter(|value| !value.is_empty() && value.bytes().all(|byte| byte.is_ascii_digit()));
    #[cfg(unix)]
    {
        uid.unwrap_or_else(unix_uid)
    }
    #[cfg(not(unix))]
    {
        uid.unwrap_or_else(|| "0".to_owned())
    }
}

#[cfg(unix)]
fn unix_uid() -> String {
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
}

pub(super) fn default_session_name() -> Result<String> {
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
    Ok(non_empty_session_name(raw.trim()))
}

fn non_empty_session_name(raw: &str) -> String {
    let sanitized = sanitize_session_name(raw);
    if sanitized.is_empty() {
        "session".to_owned()
    } else {
        sanitized
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_name_falls_back_when_sanitized_empty() {
        assert_eq!(non_empty_session_name("////"), "session");
    }

    #[test]
    fn session_name_uses_sanitized_text() {
        assert_eq!(non_empty_session_name("hello there"), "hello-there");
    }
}
