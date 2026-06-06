use std::path::Path;

use crate::command::{command_output, output_detail};
use crate::error::{Error, Result};
use dotfiles_common::process::argv;

use super::{backend_patch, frontend_patch};

const AD_HOC_ENTITLEMENTS: &str = r#"<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.cs.disable-library-validation</key>
  <true/>
</dict>
</plist>
"#;

pub(super) fn patch(frontend_dir: &Path, backend_index: &Path, beta_app: &Path) -> Result<()> {
    if !frontend_dir.exists() {
        return Err(Error::CommandFailed(format!(
            "Raycast Beta frontend directory not found: {}",
            frontend_dir.display()
        )));
    }
    if !backend_index.exists() {
        return Err(Error::CommandFailed(format!(
            "Raycast Beta backend entrypoint not found: {}",
            backend_index.display()
        )));
    }

    let mut changed = false;
    let mut saw_auth_store = false;
    let mut saw_auth_store_patch = false;
    for entry in fs_err::read_dir(frontend_dir)? {
        let path = entry?.path();
        if path.extension().and_then(|extension| extension.to_str()) != Some("js") {
            continue;
        }

        let source = fs_err::read_to_string(&path)?;
        if !frontend_patch::is_auth_store_chunk(&source) {
            continue;
        }
        let (patched, status) = frontend_patch::patch_javascript(&source);
        saw_auth_store |= status.auth_store_seen;
        saw_auth_store_patch |= status.auth_store_dev_user_patch;
        if patched != source {
            write_raycast_app_file(&path, patched)?;
            changed = true;
        }
    }

    let backend_source = fs_err::read_to_string(backend_index)?;
    let (backend_patched, backend_status) = backend_patch::patch_javascript(&backend_source);
    if backend_patched != backend_source {
        write_raycast_app_file(backend_index, backend_patched)?;
        changed = true;
    }

    if saw_auth_store && !saw_auth_store_patch {
        return Err(Error::CommandFailed(
            "Raycast Beta frontend auth store patch point not found".into(),
        ));
    }
    if !backend_status.dev_user_patch {
        return Err(Error::CommandFailed(
            "Raycast Beta backend auth user patch point not found".into(),
        ));
    }
    if !backend_status.dev_user_event_patch {
        return Err(Error::CommandFailed(
            "Raycast Beta backend auth notification patch point not found".into(),
        ));
    }
    if changed {
        eprintln!("info: Patched Raycast Beta bundle; ensuring app bundle signature...");
    } else {
        eprintln!("info: Raycast Beta bundle already patched; ensuring app bundle signature...");
    }
    codesign_beta_app(beta_app)?;
    clear_quarantine(beta_app)?;
    Ok(())
}

fn write_raycast_app_file(path: &Path, contents: String) -> Result<()> {
    fs_err::write(path, contents).map_err(|err| {
        if err.kind() == std::io::ErrorKind::PermissionDenied {
            return Error::CommandFailed(format!(
                "macOS blocked writing to Raycast Beta app bundle: {}\n\
                 Grant App Management permission to the terminal app running this command \
                 in System Settings > Privacy & Security > App Management, then restart that \
                 terminal and rerun `chezmoi-support raycast-beta-patch`.\n\
                 If Raycast Beta was downloaded outside the App Store, you may also need to run \
                 `xattr -dr com.apple.quarantine \"/Applications/Raycast Beta.app\"`.",
                path.display()
            ));
        }
        err.into()
    })
}

fn codesign_beta_app(beta_app: &Path) -> Result<()> {
    let entitlements = tempfile::Builder::new()
        .prefix("raycast-entitlements")
        .suffix(".plist")
        .tempfile()?;
    fs_err::write(entitlements.path(), AD_HOC_ENTITLEMENTS)?;
    let entitlements_path = entitlements.path().to_string_lossy();
    let beta_app = beta_app
        .to_str()
        .ok_or_else(|| Error::CommandFailed("invalid Raycast Beta app path".into()))?;
    let output = command_output(&argv([
        "codesign",
        "--force",
        "--deep",
        "--preserve-metadata=flags,runtime",
        "--entitlements",
        &entitlements_path,
        "--sign",
        "-",
        beta_app,
    ]))?;
    if output.status.success() {
        return Ok(());
    }

    let detail = output_detail(&output);
    Err(Error::CommandFailed(format!(
        "Raycast Beta app re-sign failed: {detail}"
    )))
}

fn clear_quarantine(beta_app: &Path) -> Result<()> {
    let beta_app = beta_app
        .to_str()
        .ok_or_else(|| Error::CommandFailed("invalid Raycast Beta app path".into()))?;
    let output = command_output(&argv(["xattr", "-dr", "com.apple.quarantine", beta_app]))?;
    if output.status.success() {
        return Ok(());
    }

    let detail = output_detail(&output);
    if detail.contains("No such xattr") {
        return Ok(());
    }
    Err(Error::CommandFailed(format!(
        "failed to clear Raycast Beta quarantine attribute: {detail}"
    )))
}
