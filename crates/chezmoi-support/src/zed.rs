use flate2::read::GzDecoder;

use crate::context::{Options, context_with_options};
use crate::error::Result;
use dotfiles_common::fs::{copy_dir_recursive, remove_dir_if_exists, write_text_if_changed};

use crate::fs::first_dir;
use crate::github::latest_tag;
use dotfiles_common::http::Client;

pub fn install_catppuccin_theme(options: &Options) -> Result<()> {
    let ctx = context_with_options(options)?;
    let client = Client::new("nix-dotfiles-chezmoi-support")?;
    let theme_tag = latest_tag("catppuccin/zed")?;
    let icons_tag = latest_tag("catppuccin/zed-icons")?;

    let themes_dir = ctx.home_dir.join(".config/zed/themes");
    fs_err::create_dir_all(&themes_dir)?;
    let theme = client.text(&format!(
        "https://github.com/catppuccin/zed/releases/download/{theme_tag}/catppuccin-pink.json"
    ))?;
    let theme_path = themes_dir.join("catppuccin-pink.json");
    if write_text_if_changed(&theme_path, &theme)? {
        eprintln!("success: Theme installed to {}", theme_path.display());
    }

    let zed_config = ctx.home_dir.join(".config/zed");
    let temp = tempfile::Builder::new()
        .prefix("chezmoi-script")
        .tempdir()?;
    let icons_archive = client.reader(&format!(
        "https://codeload.github.com/catppuccin/zed-icons/tar.gz/{icons_tag}"
    ))?;
    tar::Archive::new(GzDecoder::new(icons_archive)).unpack(temp.path())?;
    let root = first_dir(temp.path())?;
    fs_err::create_dir_all(zed_config.join("icon_themes"))?;
    fs_err::copy(
        root.join("icon_themes/catppuccin-icons.json"),
        zed_config.join("icon_themes/catppuccin-icons.json"),
    )?;
    remove_dir_if_exists(zed_config.join("icons"))?;
    copy_dir_recursive(&root.join("icons"), &zed_config.join("icons"))?;
    eprintln!("success: Icon theme installed to {}", zed_config.display());
    Ok(())
}
