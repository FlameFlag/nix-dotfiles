mod mcp;
mod startup_pane_color;
mod trust_overlay;

use std::ffi::OsString;

use crate::{Result, codex_bin, run_inherit};

use startup_pane_color::StartupPaneColor;
use trust_overlay::create_trust_overlay;

/// Runs the Codex profile for `zellij-theme-run`.
///
/// # Errors
///
/// Returns an error if the trust overlay cannot be created or Codex cannot be
/// executed.
pub fn run_with_args(args: Vec<OsString>) -> Result<i32> {
    let _startup_pane_color = StartupPaneColor::start();

    let overlay = create_trust_overlay()?;
    let codex = codex_bin()?;
    let command = duct::cmd(codex, args)
        .env("CODEX_HOME", overlay.path())
        .unchecked();
    run_inherit(&command)
}
