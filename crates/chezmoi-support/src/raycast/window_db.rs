use std::collections::HashMap;
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};

use crate::command::{command_output, command_output_with_stdin, output_detail};
use crate::error::{Error, Result};
use dotfiles_common::process::argv;

const KEYCHAIN_SERVICE: &str = "Raycast Beta";
const DATABASE_KEYCHAIN_ACCOUNT: &str = "database_key";
const DATABASE_PASSPHRASE_SALT: &str = "yvkwWXzxPPBAqY2tmaKrB*DvYjjMaeEf";
const EXTENSION_ID: &str = "e:r:window-management";
const CLASSIC_COMMAND_PREFIX: &str = "builtin_command_windowManagement";
const BETA_COMMAND_PREFIX: &str = "c:r:window-management::-::";

// Raycast Beta stores command settings and window layouts in an encrypted app
// database. Reusing Raycast's bundled native binding avoids guessing the schema
// and lets Raycast perform its own consistency checks before checkpointing.
const APPLY_SCRIPT: &str = r#"
const fs = require("node:fs");
const [supportDir, nativeBindingPath] = process.argv.slice(1);
const payload = JSON.parse(fs.readFileSync(0, "utf8"));
const data = require(nativeBindingPath);

(async () => {
  const db = new data.DatabaseClient(supportDir, payload.password, () => {});
  try {
    const status = db.getDatabaseStatus();
    if (!status.allHealthy) {
      throw new Error(`Raycast Beta database is not healthy: ${JSON.stringify(status)}`);
    }

    const settings = db.settings;
    await settings.sanityCheck();
    for (const row of await settings.allCommandSettingsForExtension(payload.extensionId)) {
      if (row.macosHotkey !== undefined) {
        await settings.updateCommandSettings(row.id, { ...row, macosHotkey: null });
      }
    }
    for (const command of payload.commands) {
      if (await settings.getCommandSettings(command.id)) {
        await settings.updateCommandSettings(command.id, command);
      } else {
        await settings.addCommandSettings(command);
      }
    }

    const windowManagement = db.windowManagement;
    const existingByName = new Map((await windowManagement.list()).map((group) => [group.name, group]));
    for (const group of payload.layoutGroups) {
      if (!group || typeof group !== "object" || Array.isArray(group)) {
        throw new Error("invalid Raycast Beta layout group");
      }
      if (typeof group.name !== "string" || group.name.trim() === "") {
        throw new Error("Raycast Beta layout group missing name");
      }
      if (!Array.isArray(group.layouts)) {
        throw new Error(`Raycast Beta layout group missing layouts: ${group.name}`);
      }

      const row = { ...group, name: group.name.trim() };
      const existing = row.id ? await windowManagement.getOne(row.id) : existingByName.get(row.name);
      if (existing) {
        await windowManagement.updateOne(existing.id, row);
      } else {
        await windowManagement.save(row);
      }
    }

    await db.walCheckpointAll();
  } finally {
    db.shutdown();
  }
})().catch((error) => {
  console.error(error && error.stack ? error.stack : String(error));
  process.exit(1);
});
"#;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WindowConfig {
    #[serde(default)]
    hotkeys: HashMap<String, Option<String>>,
    #[serde(default)]
    disabled_commands: Vec<String>,
    #[serde(default, alias = "layouts")]
    layout_groups: Vec<Value>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ApplyPayload {
    password: String,
    extension_id: &'static str,
    commands: Vec<CommandSettings>,
    layout_groups: Vec<Value>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CommandSettings {
    id: String,
    extension_id: &'static str,
    enabled: bool,
    favorited: bool,
    macos_hotkey: Option<Value>,
}

pub(super) fn apply_config(
    config_path: &Path,
    support_dir: &Path,
    native_binding: &Path,
) -> Result<()> {
    eprintln!("info: Applying Raycast Beta window-management settings...");
    let config: WindowConfig = serde_json::from_str(&fs_err::read_to_string(config_path)?)?;
    validate_commands(&config)?;
    let password = database_password()?;
    let payload = apply_payload(config, &password)?;
    let node = raycast_beta_node(support_dir)?;
    let command = vec![
        node.to_string_lossy().into_owned(),
        "-e".to_owned(),
        APPLY_SCRIPT.to_owned(),
        support_dir.to_string_lossy().into_owned(),
        native_binding.to_string_lossy().into_owned(),
    ];
    let output = command_output_with_stdin(&command, serde_json::to_vec(&payload)?)?;
    if output.status.success() {
        return Ok(());
    }

    let detail = output_detail(&output);
    Err(Error::CommandFailed(format!(
        "Raycast Beta native database update failed: {detail}"
    )))
}

fn validate_commands(config: &WindowConfig) -> Result<()> {
    for command in config.hotkeys.keys().chain(config.disabled_commands.iter()) {
        if !command.starts_with(CLASSIC_COMMAND_PREFIX) {
            return Err(Error::CommandFailed(format!(
                "invalid Raycast command id: {command}"
            )));
        }
    }
    Ok(())
}

fn raycast_beta_node(support_dir: &Path) -> Result<PathBuf> {
    let runtime_dir = support_dir.join("node/runtime");
    fs_err::read_dir(&runtime_dir)?
        .filter_map(|entry| {
            let entry = entry.ok()?;
            let file_name = entry.file_name();
            let file_name = file_name.to_string_lossy();
            if !file_name.starts_with("node-") || !file_name.ends_with("-darwin-arm64") {
                return None;
            }
            let node = entry.path().join("bin/node");
            node.exists().then_some(node)
        })
        .max()
        .ok_or_else(|| {
            Error::CommandFailed(format!(
                "Raycast Beta Node runtime not found in {}",
                runtime_dir.display()
            ))
        })
}

fn apply_payload(config: WindowConfig, password: &str) -> Result<ApplyPayload> {
    let mut commands = Vec::new();
    for (classic_id, value) in config.hotkeys {
        commands.push(command_settings(&classic_id, true, value.as_deref())?);
    }
    for classic_id in config.disabled_commands {
        commands.push(command_settings(&classic_id, false, None)?);
    }
    Ok(ApplyPayload {
        password: password.to_owned(),
        extension_id: EXTENSION_ID,
        commands,
        layout_groups: config.layout_groups,
    })
}

fn database_password() -> Result<String> {
    if let Ok(password) = std::env::var("RAYCAST_BETA_DATABASE_PASSWORD") {
        return Ok(password);
    }

    let database_key = database_key_from_keychain()?;
    Ok(database_passphrase(&database_key))
}

fn database_key_from_keychain() -> Result<String> {
    let output = command_output(&argv([
        "security",
        "find-generic-password",
        "-s",
        KEYCHAIN_SERVICE,
        "-a",
        DATABASE_KEYCHAIN_ACCOUNT,
        "-w",
    ]))?;
    if output.status.success() {
        return Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned());
    }
    Err(Error::CommandFailed(format!(
        "Raycast Beta database key not found in Keychain service '{KEYCHAIN_SERVICE}' account '{DATABASE_KEYCHAIN_ACCOUNT}'"
    )))
}

fn database_passphrase(database_key: &str) -> String {
    // Raycast derives the database passphrase by hashing the Keychain database
    // key with this fixed app salt before opening the native database.
    let mut hasher = Sha256::new();
    hasher.update(database_key.as_bytes());
    hasher.update(DATABASE_PASSPHRASE_SALT.as_bytes());
    hex::encode(hasher.finalize())
}

fn command_settings(
    classic_id: &str,
    enabled: bool,
    hotkey: Option<&str>,
) -> Result<CommandSettings> {
    let id = beta_command_id(classic_id)?;
    Ok(CommandSettings {
        id,
        extension_id: EXTENSION_ID,
        enabled,
        favorited: false,
        macos_hotkey: hotkey_json(hotkey)?,
    })
}

fn beta_command_id(classic_id: &str) -> Result<String> {
    let suffix = classic_id
        .strip_prefix(CLASSIC_COMMAND_PREFIX)
        .filter(|suffix| !suffix.is_empty())
        .ok_or_else(|| Error::CommandFailed(format!("invalid Raycast command id: {classic_id}")))?;
    let mut chars = suffix.chars();
    let first = chars
        .next()
        .ok_or_else(|| Error::CommandFailed(format!("invalid Raycast command id: {classic_id}")))?;
    // The old exported IDs use an UpperCamel suffix after the prefix; Beta uses
    // the same suffix with a lower-case first character under a new namespace.
    Ok(format!(
        "{}{}{}",
        BETA_COMMAND_PREFIX,
        first.to_lowercase(),
        chars.as_str()
    ))
}

fn hotkey_json(value: Option<&str>) -> Result<Option<Value>> {
    let Some(value) = value else {
        return Ok(None);
    };
    // Classic config stores hotkeys as "Modifier-...-KeyCode"; Beta expects the
    // same key code wrapped in its structured shortcut JSON.
    let (modifiers, code) = value.rsplit_once('-').unwrap_or(("", value));
    let code = code
        .parse::<i64>()
        .map_err(|_| Error::CommandFailed(format!("invalid Raycast hotkey: {value}")))?;
    let modifiers = modifiers
        .split('-')
        .filter(|part| !part.is_empty())
        .map(|part| {
            let modifier = match part {
                "Command" => "Meta",
                "Option" => "Alt",
                "Control" => "Ctrl",
                "Shift" => "Shift",
                _ => {
                    return Err(Error::CommandFailed(format!(
                        "invalid Raycast hotkey modifier: {part}"
                    )));
                }
            };
            Ok(serde_json::json!({ "modifier": modifier }))
        })
        .collect::<Result<Vec<_>>>()?;
    Ok(Some(serde_json::json!({
        "kind": {
            "type": "SingleStep",
            "shortcut": {
                "modifiers": modifiers,
                "key": { "type": "LayoutIndependent", "code": code },
            },
        },
        "locality": "Global",
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn beta_command_id_converts_classic_id() -> Result<()> {
        assert_eq!(
            beta_command_id("builtin_command_windowManagementLeftHalf")?,
            "c:r:window-management::-::leftHalf"
        );
        Ok(())
    }

    #[test]
    fn beta_hotkey_json_converts_classic_hotkey() -> Result<()> {
        let hotkey = hotkey_json(Some("Shift-Control-Option-Command-0"))?.ok_or_else(|| {
            Error::CommandFailed("expected Raycast hotkey JSON for classic hotkey".into())
        })?;
        assert_eq!(
            hotkey,
            serde_json::json!({
                "kind": {
                    "type": "SingleStep",
                    "shortcut": {
                        "modifiers": [
                            { "modifier": "Shift" },
                            { "modifier": "Ctrl" },
                            { "modifier": "Alt" },
                            { "modifier": "Meta" }
                        ],
                        "key": { "type": "LayoutIndependent", "code": 0 }
                    }
                },
                "locality": "Global"
            })
        );
        Ok(())
    }

    #[test]
    fn database_passphrase_hashes_key_then_raycast_salt() {
        assert_eq!(
            database_passphrase("database-key"),
            "828ad066b2595d5842679e7c47b73f26e466de7dd13c1bf7fe83f61a4c7428d0"
        );
    }
}
