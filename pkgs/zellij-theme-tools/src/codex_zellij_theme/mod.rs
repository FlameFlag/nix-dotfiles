mod mcp;
mod startup_pane_color;
mod trust_overlay;

use crate::{Result, codex_bin, run_inherit, wants_version_arg};

use startup_pane_color::StartupPaneColor;
use trust_overlay::create_trust_overlay;

/// Runs `codex-zellij-theme`.
///
/// # Errors
///
/// Returns an error if the trust overlay cannot be created or Codex cannot be
/// executed.
pub fn run() -> Result<i32> {
    if wants_version_arg() {
        println!("codex-zellij-theme {}", env!("CARGO_PKG_VERSION"));
        return Ok(0);
    }

    let _startup_pane_color = StartupPaneColor::start();

    let overlay = create_trust_overlay()?;
    let codex = codex_bin()?;
    let command = duct::cmd(codex, std::env::args_os().skip(1))
        .env("CODEX_HOME", overlay.path())
        .unchecked();
    run_inherit(&command)
}
