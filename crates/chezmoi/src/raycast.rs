use crate::command::{command_output, run_command};
use crate::context::{Options, Os, context_with_options, os_with_options};
use crate::error::Result;
use dotfiles_common::process::{self, argv};

const RAYCAST_BETA_APP: &str = "/Applications/Raycast Beta.app";

pub fn patch_beta_user(options: &Options) -> Result<()> {
    if os_with_options(options) != Os::Darwin {
        return Ok(());
    }

    if process::path_of("node").is_none() {
        eprintln!("warn: node not found; skipping Raycast Beta user patch");
        return Ok(());
    }

    if !std::path::Path::new(RAYCAST_BETA_APP).exists() {
        eprintln!("warn: Raycast Beta not found; skipping Raycast Beta user patch");
        return Ok(());
    }

    let ctx = context_with_options(options)?;
    let script = ctx.home_dir.join(".local/bin/raycast-beta-write-user.cjs");
    if !script.is_file() {
        eprintln!(
            "warn: {} not found; skipping Raycast Beta user patch",
            script.display()
        );
        return Ok(());
    }

    let _ = command_output(&argv(["killall", "Raycast Beta"]));
    let script = script.to_string_lossy().into_owned();
    run_command(&argv(["node", &script]))
}
