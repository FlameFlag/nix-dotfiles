use crate::command::run_command;
use crate::context::{Options, context_with_options};
use crate::error::{Error, Result};
use dotfiles_common::fs::{copy_dir_recursive, remove_dir_if_exists};
use dotfiles_common::process::{self, argv};

const YAZI_PLUGINS_REV: &str = "5d5c4803dd12bab4e4f19d606f8db0c871e6bec5";
const SYSTEM_CLIPBOARD_REV: &str = "75a53300bed1946c6d488d42efc34864ea26ca85";
const STARSHIP_REV: &str = "a83710153ab5625a64ef98d55e6ddad480a3756f";

fn clone_rev(repo: &str, rev: &str, dst: &std::path::Path) -> Result<()> {
    run_command(&[
        "git".to_owned(),
        "init".to_owned(),
        "--quiet".to_owned(),
        dst.to_string_lossy().into_owned(),
    ])?;

    let dst = dst.to_string_lossy().into_owned();
    run_command(&argv(["git", "-C", &dst, "remote", "add", "origin", repo]))?;
    run_command(&argv([
        "git",
        "-C",
        &dst,
        "fetch",
        "--depth",
        "1",
        "--no-tags",
        "--quiet",
        "origin",
        rev,
    ]))?;
    run_command(&argv([
        "git",
        "-C",
        &dst,
        "checkout",
        "--detach",
        "--quiet",
        "FETCH_HEAD",
    ]))?;
    Ok(())
}

pub fn install_plugins(options: &Options) -> Result<()> {
    if process::path_of("git").is_none() {
        return Err(Error::CommandFailed("git not found".into()));
    }
    let ctx = context_with_options(options)?;
    let plugins_dir = ctx.home_dir.join(".config/yazi/plugins");
    let flavors_dir = ctx.home_dir.join(".config/yazi/flavors");
    fs_err::create_dir_all(&plugins_dir)?;
    fs_err::create_dir_all(flavors_dir)?;
    let temp = tempfile::Builder::new()
        .prefix("chezmoi-script")
        .tempdir()?;
    eprintln!("info: Downloading plugins repository...");
    clone_rev(
        "https://github.com/yazi-rs/plugins.git",
        YAZI_PLUGINS_REV,
        temp.path(),
    )?;
    remove_dir_if_exists(temp.path().join(".git"))?;
    for plugin in ["diff", "full-border", "smart-enter", "smart-paste", "git"] {
        eprintln!("info: Installing plugin {plugin}...");
        let dst = plugins_dir.join(format!("{plugin}.yazi"));
        remove_dir_if_exists(&dst)?;
        copy_dir_recursive(&temp.path().join(format!("{plugin}.yazi")), &dst)?;
    }
    for (name, repo, rev) in [
        (
            "system-clipboard",
            "https://github.com/orhnk/system-clipboard.yazi.git",
            SYSTEM_CLIPBOARD_REV,
        ),
        (
            "starship",
            "https://github.com/Rolv-Apneseth/starship.yazi.git",
            STARSHIP_REV,
        ),
    ] {
        eprintln!("info: Installing plugin {name}...");
        let dst = plugins_dir.join(format!("{name}.yazi"));
        remove_dir_if_exists(&dst)?;
        clone_rev(repo, rev, &dst)?;
        remove_dir_if_exists(dst.join(".git"))?;
    }
    eprintln!("success: Yazi plugins installed");
    Ok(())
}
