use std::time::Duration;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum TerminalThemeMode {
    Dark,
    Light,
}

pub(crate) fn query_terminal_theme(timeout: Duration) -> Option<TerminalThemeMode> {
    imp::query_terminal_theme(timeout)
}

#[cfg(test)]
fn parse_terminal_theme_report(buffer: &[u8]) -> Option<TerminalThemeMode> {
    let text = std::str::from_utf8(buffer).ok()?;
    parse_host_theme_report(text).or_else(|| parse_osc11_background(text).map(theme_mode_from_rgb))
}

fn parse_host_theme_report(text: &str) -> Option<TerminalThemeMode> {
    if text.contains("\u{1b}[?997;1n") {
        Some(TerminalThemeMode::Dark)
    } else if text.contains("\u{1b}[?997;2n") {
        Some(TerminalThemeMode::Light)
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

fn theme_mode_from_rgb((r, g, b): (u8, u8, u8)) -> TerminalThemeMode {
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
        TerminalThemeMode::Light
    } else {
        TerminalThemeMode::Dark
    }
}

#[cfg(unix)]
mod imp {
    use super::*;
    use std::io;
    use std::os::fd::OwnedFd;
    use std::time::{Duration, Instant};

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

    pub(super) fn query_terminal_theme(timeout: Duration) -> Option<TerminalThemeMode> {
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

    pub(super) fn query_terminal_theme(_timeout: Duration) -> Option<TerminalThemeMode> {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn terminal_theme_report_prefers_csi_997() {
        assert_eq!(
            parse_terminal_theme_report(b"\x1b]11;rgb:ffff/ffff/ffff\x1b\\\x1b[?997;1n"),
            Some(TerminalThemeMode::Dark)
        );
        assert_eq!(
            parse_terminal_theme_report(b"\x1b[?997;2n"),
            Some(TerminalThemeMode::Light)
        );
    }

    #[test]
    fn terminal_theme_report_falls_back_to_osc11_background() {
        assert_eq!(
            parse_terminal_theme_report(b"\x1b]11;rgb:3030/3434/4646\x1b\\"),
            Some(TerminalThemeMode::Dark)
        );
        assert_eq!(
            parse_terminal_theme_report(b"\x1b]11;rgb:efff/f1f1/f5f5\x07"),
            Some(TerminalThemeMode::Light)
        );
    }

    #[test]
    fn parses_variable_width_rgb_components() {
        assert_eq!(parse_rgb_color("rgb:f/f/f"), Some((255, 255, 255)));
        assert_eq!(parse_rgb_color("rgb:00/80/ff"), Some((0, 128, 255)));
        assert_eq!(parse_rgb_color("rgb:3030/3434/4646"), Some((48, 52, 70)));
    }
}
