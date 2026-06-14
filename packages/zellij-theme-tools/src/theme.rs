use std::time::Duration;

use crate::terminal_theme::{TerminalThemeMode, query_terminal_theme};

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
    name: "catppuccin-frappe-pink",
    colors: Colors {
        fg: "#c6d0f5",
        bg: "#303446",
    },
};

pub const LATTE: Theme = Theme {
    name: "catppuccin-latte-pink",
    colors: Colors {
        fg: "#4c4f69",
        bg: "#eff1f5",
    },
};

#[must_use]
pub fn detect_theme() -> Theme {
    detect_terminal_theme().unwrap_or_else(detect_system_theme)
}

#[must_use]
pub fn detect_system_theme() -> Theme {
    system_theme_mode()
        .map(theme_for_terminal_mode)
        .unwrap_or(FRAPPE)
}

#[must_use]
pub fn detect_terminal_theme() -> Option<Theme> {
    query_terminal_theme(Duration::from_millis(100)).map(theme_for_terminal_mode)
}

fn theme_for_terminal_mode(mode: TerminalThemeMode) -> Theme {
    match mode {
        TerminalThemeMode::Dark => FRAPPE,
        TerminalThemeMode::Light => LATTE,
    }
}

#[cfg(target_os = "macos")]
fn system_theme_mode() -> Option<TerminalThemeMode> {
    let output = std::process::Command::new("defaults")
        .args(["read", "-g", "AppleInterfaceStyle"])
        .output()
        .ok()?;
    if output.status.success() {
        theme_mode_from_text(&String::from_utf8_lossy(&output.stdout))
    } else {
        Some(TerminalThemeMode::Light)
    }
}

#[cfg(any(
    target_os = "linux",
    target_os = "freebsd",
    target_os = "dragonfly",
    target_os = "netbsd",
    target_os = "openbsd"
))]
fn system_theme_mode() -> Option<TerminalThemeMode> {
    command_stdout(
        "gsettings",
        &["get", "org.gnome.desktop.interface", "color-scheme"],
    )
    .and_then(|text| theme_mode_from_text(&text))
    .or_else(|| {
        command_stdout(
            "gsettings",
            &["get", "org.gnome.desktop.interface", "gtk-theme"],
        )
        .and_then(|text| theme_mode_from_text(&text))
    })
}

#[cfg(windows)]
fn system_theme_mode() -> Option<TerminalThemeMode> {
    let text = command_stdout(
        "reg",
        &[
            "query",
            r"HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize",
            "/v",
            "AppsUseLightTheme",
        ],
    )?;
    if text.contains("0x0") {
        Some(TerminalThemeMode::Dark)
    } else if text.contains("0x1") {
        Some(TerminalThemeMode::Light)
    } else {
        None
    }
}

#[cfg(not(any(
    target_os = "macos",
    target_os = "linux",
    target_os = "freebsd",
    target_os = "dragonfly",
    target_os = "netbsd",
    target_os = "openbsd",
    windows
)))]
fn system_theme_mode() -> Option<TerminalThemeMode> {
    None
}

#[cfg(any(
    target_os = "linux",
    target_os = "freebsd",
    target_os = "dragonfly",
    target_os = "netbsd",
    target_os = "openbsd",
    windows
))]
fn command_stdout(program: &str, args: &[&str]) -> Option<String> {
    let output = std::process::Command::new(program)
        .args(args)
        .output()
        .ok()?;
    output
        .status
        .success()
        .then(|| String::from_utf8_lossy(&output.stdout).into_owned())
}

fn theme_mode_from_text(text: &str) -> Option<TerminalThemeMode> {
    let text = text.trim().to_ascii_lowercase();
    if text.contains("dark") {
        Some(TerminalThemeMode::Dark)
    } else if text.contains("light") {
        Some(TerminalThemeMode::Light)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn theme_mode_from_text_detects_common_names() {
        assert_eq!(
            theme_mode_from_text("'prefer-dark'"),
            Some(TerminalThemeMode::Dark)
        );
        assert_eq!(
            theme_mode_from_text("Adwaita-light"),
            Some(TerminalThemeMode::Light)
        );
        assert_eq!(theme_mode_from_text("default"), None);
    }
}
