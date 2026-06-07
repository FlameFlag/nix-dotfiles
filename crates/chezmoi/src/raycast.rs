use std::path::PathBuf;

use crate::context::{Options, Os, os_with_options};
use crate::error::Result;

mod backend_patch;
mod bundle;
mod frontend_patch;
mod local_user;

const BETA_APP: &str = "/Applications/Raycast Beta.app";
const BETA_APP_ENV: &str = "RAYCAST_BETA_APP";
const BETA_DESKTOP_RESOURCES: &str =
    "Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources";

pub fn beta_patch(options: &Options) -> Result<()> {
    if os_with_options(options) != Os::Darwin {
        return Ok(());
    }

    let beta_app = BetaAppPaths::new();
    if beta_app.bundle.exists() {
        return bundle::patch(
            &beta_app.frontend_dir,
            &beta_app.backend_index,
            &beta_app.bundle,
        );
    }

    Ok(())
}

struct BetaAppPaths {
    bundle: PathBuf,
    frontend_dir: PathBuf,
    backend_index: PathBuf,
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
        }
    }
}
