#![cfg_attr(test, allow(clippy::expect_used, clippy::panic, clippy::unwrap_used))]

mod codex;
mod error;
mod process;
mod session_name;
mod terminal_theme;
mod theme;
mod zellij;

pub mod btop_auto_theme;
pub mod codex_zellij_theme;
pub mod helix_auto_theme;
pub mod program;
pub mod zellij_auto_theme;

pub use codex::{codex_bin, home_dir};
pub use error::{Error, Result};
pub use process::{exit_code, exit_with_result, run_inherit, run_silent};
pub use session_name::sanitize_session_name;
pub use theme::{
    Colors, FRAPPE, LATTE, Theme, detect_system_theme, detect_terminal_theme, detect_theme,
};
pub use zellij::{reset_pane_color, send_focus_gained, set_pane_color, write_pane_color_override};
