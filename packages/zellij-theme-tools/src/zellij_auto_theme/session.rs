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
