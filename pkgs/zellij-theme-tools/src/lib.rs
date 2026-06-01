#![cfg_attr(test, allow(clippy::expect_used, clippy::panic, clippy::unwrap_used))]

use std::ffi::OsString;
use std::path::{Path, PathBuf};
use std::process::ExitStatus;
use std::time::{Duration, Instant};
use std::{
    io::{IsTerminal, Write},
    sync::Mutex,
};

use directories::BaseDirs;
use thiserror::Error;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Colors {
    pub fg: &'static str,
    pub bg: &'static str,
}

#[derive(Debug, Clone, Copy)]
pub struct Theme {
    pub name: &'static str,
    pub colors: Colors,
}

pub const FRAPPE: Theme = Theme {
    name: "catppuccin-frappe",
    colors: Colors {
        fg: "#c6d0f5",
        bg: "#303446",
    },
};

pub const LATTE: Theme = Theme {
    name: "catppuccin-latte",
    colors: Colors {
        fg: "#4c4f69",
        bg: "#eff1f5",
    },
};

#[derive(Debug, Error)]
pub enum Error {
    #[error(transparent)]
    Io(#[from] std::io::Error),
    #[error("HOME is not set")]
    HomeMissing,
    #[error("codex executable not found")]
    CodexNotFound,
    #[error(transparent)]
    Toml(#[from] toml_edit::TomlError),
    #[error("invalid Codex config TOML shape")]
    InvalidCodexConfig,
}

pub type Result<T> = std::result::Result<T, Error>;

#[must_use]
pub fn detect_theme() -> Theme {
    detect_terminal_theme().unwrap_or_else(detect_system_theme)
}

#[must_use]
pub fn detect_system_theme() -> Theme {
    if matches!(dark_light::detect(), Ok(dark_light::Mode::Light)) {
        LATTE
    } else {
        FRAPPE
    }
}

#[must_use]
pub fn detect_terminal_theme() -> Option<Theme> {
    query_terminal_theme(Duration::from_millis(100)).map(ThemeMode::theme)
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ThemeMode {
    Dark,
    Light,
}

impl ThemeMode {
    fn theme(self) -> Theme {
        match self {
            Self::Dark => FRAPPE,
            Self::Light => LATTE,
        }
    }
}

fn query_terminal_theme(timeout: Duration) -> Option<ThemeMode> {
    imp::query_terminal_theme(timeout)
}

#[cfg(test)]
fn parse_terminal_theme_report(buffer: &[u8]) -> Option<ThemeMode> {
    let text = std::str::from_utf8(buffer).ok()?;
    parse_host_theme_report(text).or_else(|| parse_osc11_background(text).map(theme_mode_from_rgb))
}

fn parse_host_theme_report(text: &str) -> Option<ThemeMode> {
    if text.contains("\u{1b}[?997;1n") {
        Some(ThemeMode::Dark)
    } else if text.contains("\u{1b}[?997;2n") {
        Some(ThemeMode::Light)
    } else {
        None
    }
}

fn parse_osc11_background(text: &str) -> Option<(u8, u8, u8)> {
    let mut rest = text;
    while let Some(start) = rest.find("\u{1b}]11;") {
        let value_start = start + "\u{1b}]11;".len();
        let after_prefix = &rest[value_start..];
        let (value, after_value) = match (after_prefix.find('\u{7}'), after_prefix.find("\u{1b}\\"))
        {
            (Some(bell), Some(st)) if bell < st => {
                (&after_prefix[..bell], &after_prefix[bell + 1..])
            }
            (Some(bell), None) => (&after_prefix[..bell], &after_prefix[bell + 1..]),
            (_, Some(st)) => (&after_prefix[..st], &after_prefix[st + 2..]),
            (None, None) => return None,
        };
        if let Some(rgb) = parse_rgb_color(value) {
            return Some(rgb);
        }
        rest = after_value;
    }
    None
}

fn parse_rgb_color(value: &str) -> Option<(u8, u8, u8)> {
    let value = value.strip_prefix("rgb:")?;
    let mut parts = value.split('/');
    let r = parse_color_component(parts.next()?)?;
    let g = parse_color_component(parts.next()?)?;
    let b = parse_color_component(parts.next()?)?;
    if parts.next().is_some() {
        return None;
    }
    Some((r, g, b))
}

fn parse_color_component(value: &str) -> Option<u8> {
    if value.is_empty() || value.len() > 4 || !value.bytes().all(|byte| byte.is_ascii_hexdigit()) {
        return None;
    }
    let parsed = u16::from_str_radix(value, 16).ok()?;
    let max = (1_u32 << (value.len() * 4)) - 1;
    Some(((u32::from(parsed) * 255 + (max / 2)) / max) as u8)
}

fn theme_mode_from_rgb((r, g, b): (u8, u8, u8)) -> ThemeMode {
    // WCAG relative luminance, using sRGB transfer into a linear-light space.
    let channel = |value: u8| {
        let value = f64::from(value) / 255.0;
        if value <= 0.04045 {
            value / 12.92
        } else {
            ((value + 0.055) / 1.055).powf(2.4)
        }
    };
    let luminance = 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
    if luminance > 0.5 {
        ThemeMode::Light
    } else {
        ThemeMode::Dark
    }
}

#[cfg(unix)]
mod imp {
    use super::*;
    use std::io;
    use std::os::fd::OwnedFd;
    use std::time::Duration;

    use fs_err::OpenOptions;

    struct Tty {
        reader: OwnedFd,
        writer: OwnedFd,
        original_flags: rustix::fs::OFlags,
        original_termios: Option<rustix::termios::Termios>,
    }

    impl Tty {
        fn open() -> io::Result<Self> {
            let stdin = std::io::stdin();
            let stdout = std::io::stdout();
            let reader = rustix::io::dup(&stdin);
            let writer = rustix::io::dup(&stdout);
            match (reader, writer) {
                (Ok(reader), Ok(writer))
                    if rustix::termios::isatty(&reader) && rustix::termios::isatty(&writer) =>
                {
                    Self::new(reader, writer)
                }
                _ => {
                    let reader = OpenOptions::new().read(true).open("/dev/tty")?;
                    let writer = OpenOptions::new().write(true).open("/dev/tty")?;
                    Self::new(reader.into(), writer.into())
                }
            }
        }

        fn new(reader: OwnedFd, writer: OwnedFd) -> io::Result<Self> {
            let original_flags = rustix::fs::fcntl_getfl(&reader)?;
            rustix::fs::fcntl_setfl(&reader, original_flags | rustix::fs::OFlags::NONBLOCK)?;

            let mut original_termios = None;
            if rustix::termios::isatty(&reader)
                && let Ok(saved) = rustix::termios::tcgetattr(&reader)
            {
                let mut raw = saved.clone();
                raw.make_raw();
                if rustix::termios::tcsetattr(&reader, rustix::termios::OptionalActions::Now, &raw)
                    .is_ok()
                {
                    original_termios = Some(saved);
                }
            }

            Ok(Self {
                reader,
                writer,
                original_flags,
                original_termios,
            })
        }

        fn write_all(&mut self, bytes: &[u8]) -> io::Result<()> {
            let mut remaining = bytes;
            while !remaining.is_empty() {
                let written = rustix::io::write(&self.writer, remaining)?;
                remaining = &remaining[written..];
            }
            Ok(())
        }

        fn read_available(&mut self, buffer: &mut Vec<u8>) -> io::Result<()> {
            let mut chunk = [0_u8; 256];
            loop {
                match rustix::io::read(&self.reader, chunk.as_mut_slice()) {
                    Ok(0) => return Ok(()),
                    Ok(count) => buffer.extend_from_slice(&chunk[..count]),
                    Err(err) if err == rustix::io::Errno::AGAIN => return Ok(()),
                    Err(err) if err == rustix::io::Errno::INTR => return Ok(()),
                    Err(err) => return Err(err.into()),
                }
            }
        }

        fn poll_readable(&self, timeout: Duration) -> io::Result<bool> {
            let mut fd = rustix::event::PollFd::new(&self.reader, rustix::event::PollFlags::IN);
            let timeout = rustix::event::Timespec::try_from(timeout).ok();
            let count = rustix::event::poll(std::slice::from_mut(&mut fd), timeout.as_ref())?;
            Ok(count > 0 && fd.revents().contains(rustix::event::PollFlags::IN))
        }

        fn read_until<T>(
            &mut self,
            timeout: Duration,
            mut parse: impl FnMut(&[u8]) -> Option<T>,
        ) -> Option<T> {
            let deadline = Instant::now() + timeout;
            let mut buffer = Vec::new();
            loop {
                self.read_available(&mut buffer).ok()?;
                if let Some(value) = parse(&buffer) {
                    return Some(value);
                }
                let now = Instant::now();
                if now >= deadline {
                    return None;
                }
                if !self
                    .poll_readable(deadline.saturating_duration_since(now))
                    .ok()?
                {
                    return None;
                }
            }
        }
    }

    impl Drop for Tty {
        fn drop(&mut self) {
            if let Some(termios) = &self.original_termios {
                let _ = rustix::termios::tcsetattr(
                    &self.reader,
                    rustix::termios::OptionalActions::Now,
                    termios,
                );
            }
            let _ = rustix::fs::fcntl_setfl(&self.reader, self.original_flags);
        }
    }

    pub(super) fn query_terminal_theme(timeout: Duration) -> Option<ThemeMode> {
        let mut tty = Tty::open().ok()?;
        tty.write_all(b"\x1b[?996n").ok()?;
        if let Some(mode) = tty.read_until(timeout, |buffer| {
            parse_host_theme_report(std::str::from_utf8(buffer).ok()?)
        }) {
            return Some(mode);
        }

        if std::env::var_os("ZELLIJ").is_some() {
            return None;
        }

        tty.write_all(b"\x1b]11;?\x1b\\").ok()?;
        tty.read_until(timeout, |buffer| {
            parse_osc11_background(std::str::from_utf8(buffer).ok()?).map(theme_mode_from_rgb)
        })
    }
}

#[cfg(not(unix))]
mod imp {
    use super::*;

    pub(super) fn query_terminal_theme(_timeout: Duration) -> Option<ThemeMode> {
        None
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

pub fn set_pane_color(colors: Colors) {
    run_silent(
        "zellij",
        &[
            "action",
            "set-pane-color",
            "--fg",
            colors.fg,
            "--bg",
            colors.bg,
        ],
    );
}

pub fn write_pane_color_override(colors: Colors) {
    static STDOUT_LOCK: Mutex<()> = Mutex::new(());
    let Ok(_guard) = STDOUT_LOCK.lock() else {
        return;
    };

    let mut stdout = std::io::stdout().lock();
    if !stdout.is_terminal() {
        return;
    }

    let _ = write!(
        stdout,
        "\x1b]10;{}\x1b\\\x1b]11;{}\x1b\\",
        colors.fg, colors.bg
    );
    let _ = stdout.flush();
}

pub fn reset_pane_color() {
    run_silent("zellij", &["action", "set-pane-color", "--reset"]);
}

pub fn send_focus_gained(pane_id: &str) {
    run_silent(
        "zellij",
        &["action", "write", "--pane-id", pane_id, "27", "91", "73"],
    );
}

/// Finds the Codex executable.
///
/// # Errors
///
/// Returns an error if Codex cannot be found or the home directory is unavailable.
pub fn codex_bin() -> Result<PathBuf> {
    let home = home_dir()?;
    codex_bin_from(
        &home,
        std::env::var_os("CODEX_ZELLIJ_THEME_CODEX_BIN"),
        || which::which("codex").ok(),
    )
}

fn codex_bin_from(
    home: &Path,
    configured_path: Option<OsString>,
    find_on_path: impl FnOnce() -> Option<PathBuf>,
) -> Result<PathBuf> {
    if let Some(path) = configured_path
        .map(PathBuf::from)
        .filter(|path| path.is_file())
    {
        return Ok(path);
    }

    let patched = home.join(".local/opt/codex-patched/bin/codex");
    if patched.is_file() {
        return Ok(patched);
    }

    if let Some(path) = find_on_path() {
        return Ok(path);
    }
    for candidate in [".bun/bin/codex", ".npm/bin/codex", ".local/bin/codex"] {
        let path = home.join(candidate);
        if path.is_file() {
            return Ok(path);
        }
    }
    Err(Error::CodexNotFound)
}

/// Returns the current user's home directory.
///
/// # Errors
///
/// Returns an error if the home directory cannot be determined.
pub fn home_dir() -> Result<PathBuf> {
    BaseDirs::new()
        .map(|dirs| dirs.home_dir().to_path_buf())
        .ok_or(Error::HomeMissing)
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

#[must_use]
pub fn sanitize_session_name(raw: &str) -> String {
    let mut output = String::new();
    let mut pending_dash = false;
    for ch in raw.chars() {
        if ch.is_ascii_alphanumeric() || matches!(ch, '_' | '.' | '-') {
            if pending_dash && !output.is_empty() {
                output.push('-');
            }
            pending_dash = false;
            output.push(ch);
        } else {
            pending_dash = true;
        }
    }
    output
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_names_are_squeezed_and_trimmed() {
        assert_eq!(sanitize_session_name("repo"), "repo");
        assert_eq!(sanitize_session_name("  hello///there!! "), "hello-there");
        assert_eq!(sanitize_session_name("a_b.c-d"), "a_b.c-d");
    }

    #[test]
    fn terminal_theme_report_prefers_csi_997() {
        assert_eq!(
            parse_terminal_theme_report(b"\x1b]11;rgb:ffff/ffff/ffff\x1b\\\x1b[?997;1n"),
            Some(ThemeMode::Dark)
        );
        assert_eq!(
            parse_terminal_theme_report(b"\x1b[?997;2n"),
            Some(ThemeMode::Light)
        );
    }

    #[test]
    fn terminal_theme_report_falls_back_to_osc11_background() {
        assert_eq!(
            parse_terminal_theme_report(b"\x1b]11;rgb:3030/3434/4646\x1b\\"),
            Some(ThemeMode::Dark)
        );
        assert_eq!(
            parse_terminal_theme_report(b"\x1b]11;rgb:efff/f1f1/f5f5\x07"),
            Some(ThemeMode::Light)
        );
    }

    #[test]
    fn parses_variable_width_rgb_components() {
        assert_eq!(parse_rgb_color("rgb:f/f/f"), Some((255, 255, 255)));
        assert_eq!(parse_rgb_color("rgb:00/80/ff"), Some((0, 128, 255)));
        assert_eq!(parse_rgb_color("rgb:3030/3434/4646"), Some((48, 52, 70)));
    }

    #[test]
    fn codex_bin_prefers_configured_existing_file() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let configured = temp.path().join("configured-codex");
        let path_codex = temp.path().join("path-codex");
        fs_err::write(&configured, "")?;
        fs_err::write(&path_codex, "")?;

        assert_eq!(
            codex_bin_from(
                temp.path(),
                Some(configured.clone().into_os_string()),
                || { Some(path_codex) }
            )?,
            configured
        );
        Ok(())
    }

    #[test]
    fn codex_bin_uses_home_candidates_and_path_fallback() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path_codex = temp.path().join("path-codex");
        fs_err::write(&path_codex, "")?;

        assert_eq!(
            codex_bin_from(temp.path(), None, || Some(path_codex.clone()))?,
            path_codex
        );

        let bun_codex = temp.path().join(".bun/bin/codex");
        fs_err::create_dir_all(bun_codex.parent().expect("parent"))?;
        fs_err::write(&bun_codex, "")?;
        assert_eq!(codex_bin_from(temp.path(), None, || None)?, bun_codex);
        Ok(())
    }
}
