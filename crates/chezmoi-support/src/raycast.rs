use std::path::PathBuf;

use crate::context::{Options, Os, context_with_options};
use crate::error::{Error, Result};

mod beta_scripts;
mod window_db;

const BETA_APP: &str = "/Applications/Raycast Beta.app";
const BETA_SUPPORT_DIR: &str = "Library/Application Support/com.raycast-x.macos";
const BETA_MAIN_DB: &str = "main.db";
const BETA_APP_ENV: &str = "RAYCAST_BETA_APP";
const BETA_DESKTOP_RESOURCES: &str =
    "Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources";

pub fn window_management(options: &Options) -> Result<()> {
    let ctx = context_with_options(options)?;
    if ctx.os != Os::Darwin {
        return Ok(());
    }

    let beta_app = BetaAppPaths::new();
    if beta_app.bundle.exists() {
        beta_scripts::patch(
            &beta_app.frontend_dir,
            &beta_app.backend_index,
            &beta_app.bundle,
        )?;
    }

    let config_path = ctx
        .source_dir
        .join("dot_config/raycast/window-management.json");
    if !config_path.exists() {
        eprintln!(
            "warn: Raycast window-management config not found: {}",
            config_path.display()
        );
        return Ok(());
    }

    let beta_support_dir = ctx.home_dir.join(BETA_SUPPORT_DIR);
    let beta_db = beta_support_dir.join(BETA_MAIN_DB);
    if !beta_app.bundle.exists() || !beta_db.exists() {
        return Ok(());
    }
    if !beta_app.native_binding.exists() {
        return Err(Error::CommandFailed(format!(
            "Raycast Beta native data binding not found: {}",
            beta_app.native_binding.display()
        )));
    }

    window_db::apply_config(&config_path, &beta_support_dir, &beta_app.native_binding)
}

struct BetaAppPaths {
    bundle: PathBuf,
    frontend_dir: PathBuf,
    backend_index: PathBuf,
    native_binding: PathBuf,
}

impl BetaAppPaths {
    fn new() -> Self {
        let bundle =
            std::env::var_os(BETA_APP_ENV).map_or_else(|| PathBuf::from(BETA_APP), PathBuf::from);
        let resources = bundle.join(BETA_DESKTOP_RESOURCES);
        Self {
            bundle,
            frontend_dir: resources.join("frontend"),
            backend_index: resources.join("backend/index.mjs"),
            native_binding: resources.join("backend/data.darwin-arm64.node"),
        }
    }
}
