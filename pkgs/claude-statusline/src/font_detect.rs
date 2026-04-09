//! Best-effort terminal-font detection for the default icon set.
//!
//! There is no portable cross-terminal API for "what font is rendering this
//! cell right now", and even macOS Core Text only knows what's *installed*,
//! not what the active terminal happens to be drawing with. So we use the
//! next-best signal: the terminal's own config file.
//!
//! Strategy:
//! 1. Identify the terminal via `$TERM_PROGRAM` / `$TERM` / well-known env vars
//!    (e.g. `KITTY_PID`, `ALACRITTY_LOG`).
//! 2. Read its config file from the conventional location (XDG path on Linux, the
//!    per-app `~/Library/Application Support` directory on macOS where it
//!    differs).
//! 3. If the config text contains a "nerd font" substring (case insensitive),
//!    assume the terminal is rendering with a Nerd Font and return
//!    [`IconSet::Nerd`]. Otherwise fall through to the safe text-only set.
//!
//! No caching: config files are tiny and reads are microseconds, so we'd
//! rather pick up font changes immediately than risk a stale cache.

use std::path::PathBuf;

use crate::render::icons::IconSet;

/// Known terminal emulators we can identify from the environment.
#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum Terminal {
    Ghostty,
    Kitty,
    Alacritty,
    WezTerm,
    Other,
}

/// Identify the running terminal from environment variables.
pub fn detect_terminal() -> Terminal {
    let term_program = std::env::var("TERM_PROGRAM").unwrap_or_default();
    let term = std::env::var("TERM").unwrap_or_default();

    if term_program == "ghostty" || term == "xterm-ghostty" {
        Terminal::Ghostty
    } else if term_program == "WezTerm" {
        Terminal::WezTerm
    } else if term == "xterm-kitty" || std::env::var_os("KITTY_PID").is_some() {
        Terminal::Kitty
    } else if std::env::var_os("ALACRITTY_LOG").is_some()
        || std::env::var_os("ALACRITTY_WINDOW_ID").is_some()
    {
        Terminal::Alacritty
    } else {
        Terminal::Other
    }
}

/// Resolve the config file path for a given terminal.
pub fn config_path_for(terminal: Terminal) -> Option<PathBuf> {
    let home = dirs::home_dir()?;
    let xdg_config = dirs::config_dir().unwrap_or_else(|| home.join(".config"));

    match terminal {
        Terminal::Ghostty => {
            let mac_path = home.join("Library/Application Support/com.mitchellh.ghostty/config");
            if mac_path.exists() {
                Some(mac_path)
            } else {
                Some(xdg_config.join("ghostty/config"))
            }
        }
        Terminal::WezTerm => {
            for candidate in [
                xdg_config.join("wezterm/wezterm.lua"),
                home.join(".wezterm.lua"),
            ] {
                if candidate.exists() {
                    return Some(candidate);
                }
            }
            None
        }
        Terminal::Kitty => Some(xdg_config.join("kitty/kitty.conf")),
        Terminal::Alacritty => {
            for candidate in [
                xdg_config.join("alacritty/alacritty.toml"),
                xdg_config.join("alacritty/alacritty.yml"),
            ] {
                if candidate.exists() {
                    return Some(candidate);
                }
            }
            None
        }
        Terminal::Other => None,
    }
}

/// Pick an icon set when the user hasn't specified one explicitly.
pub fn auto_select() -> IconSet {
    let terminal = detect_terminal();
    if let Some(path) = config_path_for(terminal)
        && let Ok(text) = std::fs::read_to_string(&path)
        && contains_nerd_font(&text)
    {
        return IconSet::Nerd;
    }
    IconSet::Text
}

/// True if the text contains a recognizable Nerd Font name. Catches the
/// canonical "Nerd Font" / "`NerdFont`" spellings plus the common " NF" /
/// " NFM" suffix abbreviations used by some font packagers.
pub fn contains_nerd_font(s: &str) -> bool {
    let lower = s.to_ascii_lowercase();
    if lower.contains("nerd font") || lower.contains("nerdfont") {
        return true;
    }
    // " nfm " (Nerd Font Mono) and " nf " suffixes - only match when
    // surrounded by whitespace/punct so we don't false-positive on words
    // like "snfm" or "infinite".
    lower
        .split(|c: char| !c.is_ascii_alphanumeric())
        .any(|tok| tok == "nf" || tok == "nfm")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_canonical_nerd_font_name() {
        assert!(contains_nerd_font("font-family = TX02 Nerd Font"));
        assert!(contains_nerd_font(
            "font_family JetBrainsMono Nerd Font Mono"
        ));
        assert!(contains_nerd_font("family = \"FiraCode NerdFont\""));
    }

    #[test]
    fn detects_short_suffix() {
        assert!(contains_nerd_font("font_family Hack NF"));
        assert!(contains_nerd_font("font_family Iosevka NFM"));
    }

    #[test]
    fn ignores_unrelated_text() {
        assert!(!contains_nerd_font("font-family = Menlo"));
        assert!(!contains_nerd_font("font_family = SF Mono"));
        // Don't false-positive on words containing 'nf' or 'nfm'.
        assert!(!contains_nerd_font("# infinite scrollback"));
        assert!(!contains_nerd_font("comment about snfm settings"));
    }
}
