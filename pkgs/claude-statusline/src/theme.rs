//! Terminal theme detection: dark vs light background.
//!
//! Detection strategy (in priority order):
//!
//! 1. **CLI override** (`--theme dark` / `--theme light`) – instant, no I/O.
//! 2. **Config-file parsing** – read the terminal's own config file and extract
//!    the background color. Microseconds, no terminal round-trip, works inside
//!    tmux. Covers Ghostty, Kitty, and Alacritty.
//! 3. **OSC 11 query** via `terminal-colorsaurus` – send an escape sequence to
//!    the terminal and parse its response. Works for any terminal that supports
//!    the xterm `OSC 11` protocol. Adds ~5-50 ms of latency.
//! 4. **Default** – dark (the most common terminal setup).
//!
//! Stylix / base16 users get correct detection for free: Stylix generates
//! terminal-native config files with its palette, so reading the config
//! automatically picks up Stylix-assigned colors.

use std::path::Path;
use std::time::Duration;

use clap::ValueEnum;

use crate::font_detect::{self, Terminal};

/// Dark or light terminal background.
#[derive(Copy, Clone, Debug, Eq, PartialEq, ValueEnum, Default)]
#[value(rename_all = "lower")]
pub enum ThemeMode {
    /// Auto-detect from terminal config or OSC 11 query.
    #[default]
    Auto,
    /// Force dark palette.
    Dark,
    /// Force light palette.
    Light,
}

/// Resolve the effective theme. `cli_override` is the raw `--theme` value;
/// `Auto` triggers detection, `Dark`/`Light` short-circuit immediately.
pub fn detect(cli_override: ThemeMode) -> ThemeMode {
    match cli_override {
        ThemeMode::Dark | ThemeMode::Light => cli_override,
        ThemeMode::Auto => detect_auto(),
    }
}

fn detect_auto() -> ThemeMode {
    // Fast path: parse the terminal's config file.
    if let Some(mode) = detect_from_config() {
        return mode;
    }
    // Slow path: OSC 11 query to the terminal.
    if let Some(mode) = detect_from_osc() {
        return mode;
    }
    ThemeMode::Dark
}

// ---------------------------------------------------------------------------
// Config-file-based detection
// ---------------------------------------------------------------------------

fn detect_from_config() -> Option<ThemeMode> {
    let terminal = font_detect::detect_terminal();
    let path = font_detect::config_path_for(terminal)?;
    let text = std::fs::read_to_string(&path).ok()?;

    match terminal {
        Terminal::Ghostty => detect_ghostty(&text, &path),
        Terminal::Kitty => detect_kitty(&text, &path),
        Terminal::Alacritty => detect_alacritty(&text),
        _ => None,
    }
}

/// Ghostty: look for `theme = light:X,dark:Y` (the prefix tells us the
/// mode directly) or `background = #RRGGBB`.
fn detect_ghostty(text: &str, _config_path: &Path) -> Option<ThemeMode> {
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('#') {
            continue;
        }
        // `theme = light:Foo,dark:Bar` or just `theme = SomeName`
        if let Some(val) = strip_config_key(line, "theme") {
            // Ghostty's light/dark auto-switch syntax: the *first*
            // prefix tells us what the "primary" mode is. If neither
            // prefix is present, we can't infer mode from the theme
            // name alone — fall through to background color.
            if val.starts_with("light:") {
                return Some(ThemeMode::Light);
            }
            if val.starts_with("dark:") {
                return Some(ThemeMode::Dark);
            }
            // Single theme name — check for common light theme naming
            // conventions as a heuristic.
            let lower = val.to_ascii_lowercase();
            if lower.contains("light") || lower.contains("latte") || lower.contains("dawn") {
                return Some(ThemeMode::Light);
            }
            if lower.contains("dark") || lower.contains("mocha") || lower.contains("night") {
                return Some(ThemeMode::Dark);
            }
        }
        // `background = #RRGGBB` or `background = RRGGBB`
        if let Some(val) = strip_config_key(line, "background")
            && let Some(mode) = mode_from_hex(val)
        {
            return Some(mode);
        }
    }
    None
}

/// Kitty: parse `background #RRGGBB` from the main config and any
/// included `current-theme.conf`.
fn detect_kitty(text: &str, config_path: &Path) -> Option<ThemeMode> {
    // Check includes first (theme overrides tend to live there).
    let config_dir = config_path.parent()?;
    for line in text.lines() {
        let line = line.trim();
        if let Some(inc) = line.strip_prefix("include") {
            let inc = inc.trim();
            let inc_path = config_dir.join(inc);
            if let Ok(inc_text) = std::fs::read_to_string(&inc_path)
                && let Some(mode) = kitty_bg_from_text(&inc_text)
            {
                return Some(mode);
            }
        }
    }
    kitty_bg_from_text(text)
}

fn kitty_bg_from_text(text: &str) -> Option<ThemeMode> {
    for line in text.lines() {
        let line = line.trim();
        if line.starts_with('#') {
            continue;
        }
        // Kitty uses space-separated `key value`, e.g. `background #1e1e2e`
        if let Some(rest) = line.strip_prefix("background") {
            let val = rest.trim();
            if val.is_empty() {
                continue;
            }
            return mode_from_hex(val);
        }
    }
    None
}

/// Alacritty: find `background` under `[colors.primary]` in TOML.
/// We do a simple line-scan rather than pulling in a full TOML parser.
fn detect_alacritty(text: &str) -> Option<ThemeMode> {
    let mut in_colors_primary = false;
    for line in text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with('#') {
            continue;
        }
        // Track TOML section headers.
        if trimmed.starts_with('[') {
            in_colors_primary = trimmed == "[colors.primary]";
            continue;
        }
        if in_colors_primary && let Some(val) = strip_config_key(trimmed, "background") {
            // Alacritty quotes hex values: background = "#1e1e2e"
            let val = val.trim_matches(|c| c == '"' || c == '\'');
            return mode_from_hex(val);
        }
    }

    // Alacritty also supports `import` of theme files. Check if we can
    // find a `[colors.primary]` section in any imported file.
    for line in text.lines() {
        let trimmed = line.trim();
        // `import = ["~/.config/alacritty/themes/catppuccin.toml"]`
        if trimmed.starts_with("import") || trimmed.starts_with("general.import") {
            // Extract quoted paths from the line.
            for segment in trimmed.split('"') {
                let candidate = shellexpand_tilde(segment);
                let ext = Path::new(&candidate)
                    .extension()
                    .and_then(|e| e.to_str())
                    .unwrap_or("");
                if (ext.eq_ignore_ascii_case("toml") || ext.eq_ignore_ascii_case("yml"))
                    && let Ok(inc_text) = std::fs::read_to_string(&candidate)
                    && let Some(mode) = detect_alacritty(&inc_text)
                {
                    return Some(mode);
                }
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// OSC 11 fallback
// ---------------------------------------------------------------------------

fn detect_from_osc() -> Option<ThemeMode> {
    let mut opts = terminal_colorsaurus::QueryOptions::default();
    opts.timeout = Duration::from_millis(100);
    match terminal_colorsaurus::theme_mode(opts) {
        Ok(terminal_colorsaurus::ThemeMode::Dark) => Some(ThemeMode::Dark),
        Ok(terminal_colorsaurus::ThemeMode::Light) => Some(ThemeMode::Light),
        Err(_) => None,
    }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Strip a `key = value` or `key value` prefix and return the trimmed value.
fn strip_config_key<'a>(line: &'a str, key: &str) -> Option<&'a str> {
    let rest = line.strip_prefix(key)?;
    // Must be followed by whitespace or `=`, not a longer key name.
    let first = rest.chars().next()?;
    if first != '=' && !first.is_ascii_whitespace() {
        return None;
    }
    Some(rest.trim_start_matches(|c: char| c == '=' || c.is_ascii_whitespace()))
}

/// Parse `#RRGGBB` or `RRGGBB` and classify by luminance.
fn mode_from_hex(s: &str) -> Option<ThemeMode> {
    let (r, g, b) = parse_hex_color(s)?;
    if relative_luminance(r, g, b) >= 0.5 {
        Some(ThemeMode::Light)
    } else {
        Some(ThemeMode::Dark)
    }
}

/// Parse a hex color string like `#1e1e2e`, `1e1e2e`, or `0x1e1e2e`.
fn parse_hex_color(s: &str) -> Option<(u8, u8, u8)> {
    let hex = s.trim().trim_start_matches('#').trim_start_matches("0x");
    if hex.len() != 6 || !hex.chars().all(|c| c.is_ascii_hexdigit()) {
        return None;
    }
    let r = u8::from_str_radix(&hex[0..2], 16).ok()?;
    let g = u8::from_str_radix(&hex[2..4], 16).ok()?;
    let b = u8::from_str_radix(&hex[4..6], 16).ok()?;
    Some((r, g, b))
}

/// sRGB relative luminance (simplified gamma with exponent 2.2).
/// Returns a value in `[0.0, 1.0]` where 0 is black and 1 is white.
fn relative_luminance(r: u8, g: u8, b: u8) -> f64 {
    fn linearize(c: u8) -> f64 {
        (c as f64 / 255.0).powf(2.2)
    }
    0.0722f64.mul_add(
        linearize(b),
        0.2126f64.mul_add(linearize(r), 0.7152 * linearize(g)),
    )
}

/// Expand a leading `~` to `$HOME`. Bare-minimum tilde expansion for
/// config import paths — we don't need full shell expansion here.
fn shellexpand_tilde(s: &str) -> String {
    if let Some(rest) = s.strip_prefix("~/")
        && let Some(home) = dirs::home_dir()
    {
        return home.join(rest).to_string_lossy().into_owned();
    }
    s.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_hex_variants() {
        assert_eq!(parse_hex_color("#1e1e2e"), Some((0x1e, 0x1e, 0x2e)));
        assert_eq!(parse_hex_color("1e1e2e"), Some((0x1e, 0x1e, 0x2e)));
        assert_eq!(parse_hex_color("0x1e1e2e"), Some((0x1e, 0x1e, 0x2e)));
        assert_eq!(parse_hex_color("#FFFFFF"), Some((255, 255, 255)));
    }

    #[test]
    fn parse_hex_rejects_invalid() {
        assert_eq!(parse_hex_color(""), None);
        assert_eq!(parse_hex_color("#fff"), None);
        assert_eq!(parse_hex_color("not-a-color"), None);
    }

    #[test]
    fn luminance_extremes() {
        // Black → 0.0
        assert!(relative_luminance(0, 0, 0) < 0.01);
        // White → 1.0
        assert!(relative_luminance(255, 255, 255) > 0.99);
    }

    #[test]
    fn mode_from_dark_bg() {
        // Catppuccin Mocha base
        assert_eq!(mode_from_hex("#1e1e2e"), Some(ThemeMode::Dark));
        // Gruvbox dark
        assert_eq!(mode_from_hex("#282828"), Some(ThemeMode::Dark));
    }

    #[test]
    fn mode_from_light_bg() {
        // Catppuccin Latte base
        assert_eq!(mode_from_hex("#eff1f5"), Some(ThemeMode::Light));
        // Solarized light
        assert_eq!(mode_from_hex("#fdf6e3"), Some(ThemeMode::Light));
        // White
        assert_eq!(mode_from_hex("#ffffff"), Some(ThemeMode::Light));
    }

    #[test]
    fn strip_key_equals() {
        assert_eq!(
            strip_config_key("background = #1e1e2e", "background"),
            Some("#1e1e2e")
        );
        assert_eq!(
            strip_config_key("background=#1e1e2e", "background"),
            Some("#1e1e2e")
        );
    }

    #[test]
    fn strip_key_space() {
        assert_eq!(
            strip_config_key("background #1e1e2e", "background"),
            Some("#1e1e2e")
        );
    }

    #[test]
    fn strip_key_no_match() {
        // "background-color" should NOT match "background"
        assert_eq!(
            strip_config_key("background-color = red", "background"),
            None
        );
    }

    #[test]
    fn ghostty_theme_prefix() {
        let config = "theme = light:Catppuccin Latte,dark:Catppuccin Mocha\n";
        assert_eq!(
            detect_ghostty(config, Path::new("")),
            Some(ThemeMode::Light)
        );

        let config = "theme = dark:Gruvbox,light:Gruvbox Light\n";
        assert_eq!(detect_ghostty(config, Path::new("")), Some(ThemeMode::Dark));
    }

    #[test]
    fn ghostty_theme_name_heuristic() {
        let config = "theme = Catppuccin Latte\n";
        assert_eq!(
            detect_ghostty(config, Path::new("")),
            Some(ThemeMode::Light)
        );

        let config = "theme = Rose Pine Dawn\n";
        assert_eq!(
            detect_ghostty(config, Path::new("")),
            Some(ThemeMode::Light)
        );

        let config = "theme = Catppuccin Mocha\n";
        assert_eq!(detect_ghostty(config, Path::new("")), Some(ThemeMode::Dark));
    }

    #[test]
    fn ghostty_background_color() {
        let config = "background = #eff1f5\n";
        assert_eq!(
            detect_ghostty(config, Path::new("")),
            Some(ThemeMode::Light)
        );
    }

    #[test]
    fn kitty_background() {
        let config = "font_family JetBrainsMono Nerd Font\nbackground #1e1e2e\n";
        assert_eq!(kitty_bg_from_text(config), Some(ThemeMode::Dark));

        let config = "background #eff1f5\n";
        assert_eq!(kitty_bg_from_text(config), Some(ThemeMode::Light));
    }

    #[test]
    fn alacritty_colors_primary() {
        let config = r##"
[colors.primary]
background = "#1e1e2e"
foreground = "#cdd6f4"
"##;
        assert_eq!(detect_alacritty(config), Some(ThemeMode::Dark));

        let config = r##"
[colors.primary]
background = "#eff1f5"
foreground = "#4c4f69"
"##;
        assert_eq!(detect_alacritty(config), Some(ThemeMode::Light));
    }
}
