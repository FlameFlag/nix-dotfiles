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
    if matches!(dark_light::detect(), Ok(dark_light::Mode::Light)) {
        LATTE
    } else {
        FRAPPE
    }
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
