// @ts-check

import { readFileSync } from "node:fs";
import { createRequire } from "node:module";

/**
 * @typedef {{ modifier: "Meta" | "Alt" | "Ctrl" | "Shift" }} BetaModifier
 * @typedef {{ type: "LayoutIndependent", code: number }} BetaKey
 * @typedef {{ type: "SingleStep", shortcut: { modifiers: BetaModifier[], key: BetaKey } }} BetaHotkeyKind
 * @typedef {{ kind: BetaHotkeyKind, locality: "Global" }} BetaHotkey
 * @typedef {{ id: string, extensionId: string, enabled: boolean, favorited: boolean, macosHotkey: BetaHotkey | null }} BetaCommandSettings
 * @typedef {{ id?: string, name: string, layouts: unknown[] } & Record<string, unknown>} BetaLayoutGroup
 * @typedef {{ hotkeys?: Record<string, string | null>, disabledCommands?: string[], layoutGroups?: BetaLayoutGroup[], layouts?: BetaLayoutGroup[] }} WindowManagementConfig
 * @typedef {{ id: string, name: string } & Record<string, unknown>} ExistingLayoutGroup
 * @typedef {{ list(): Promise<ExistingLayoutGroup[]>, getOne(id: string): Promise<ExistingLayoutGroup | undefined>, updateOne(id: string, value: BetaLayoutGroup): Promise<void>, save(value: BetaLayoutGroup): Promise<void> }} WindowManagementStore
 * @typedef {{ sanityCheck(): Promise<void>, allCommandSettingsForExtension(extensionId: string): Promise<Array<{ id: string, macosHotkey?: unknown }>>, getCommandSettings(id: string): Promise<unknown>, updateCommandSettings(id: string, value: BetaCommandSettings | Record<string, unknown>): Promise<void>, addCommandSettings(value: BetaCommandSettings): Promise<void> }} SettingsStore
 * @typedef {{ getDatabaseStatus(): { allHealthy: boolean } & Record<string, unknown>, settings: SettingsStore, windowManagement: WindowManagementStore, walCheckpointAll(): Promise<void>, shutdown(): void }} DatabaseClient
 * @typedef {{ DatabaseClient: new (supportDir: string, password: string, log: (message: unknown) => void) => DatabaseClient }} DataBinding
 */

const require = createRequire(import.meta.url);
const [supportDir, configPath, nativeBindingPath, databasePassword] =
  process.argv.slice(2);
if (!supportDir || !configPath || !nativeBindingPath || !databasePassword) {
  throw new Error(
    "usage: apply-raycast-beta-window-management.mjs <support-dir> <config> <binding> <database-password>",
  );
}

// Intentionally use the native data binding against a stopped Raycast Beta backend.
// The localhost uiTesting/evaluate bridge can also mutate these settings, but only
// after launching Raycast with RAYCAST_ENABLE_UI_TESTING=1, which exposes a broad
// local privileged automation/RCE surface. Keeping this helper offline avoids that.
/** @type {DataBinding} */
const data = require(nativeBindingPath);
const commandNamespace = {
  classicPrefix: "builtin_command_windowManagement",
  betaExtensionId: "e:r:window-management",
  betaCommandPrefix: "c:r:window-management::-::",
};
/** @type {Record<string, BetaModifier["modifier"]>} */
const modifierNames = {
  Command: "Meta",
  Option: "Alt",
  Control: "Ctrl",
  Shift: "Shift",
};

/**
 * Converts classic Raycast command IDs to Raycast Beta command IDs.
 * @param {string} classicId
 * @returns {string}
 */
function betaCommandId(classicId) {
  if (!classicId.startsWith(commandNamespace.classicPrefix))
    throw new Error(`invalid Raycast command id: ${classicId}`);
  const suffix = classicId.slice(commandNamespace.classicPrefix.length);
  if (!suffix) throw new Error(`invalid Raycast command id: ${classicId}`);
  return (
    commandNamespace.betaCommandPrefix +
    suffix[0].toLowerCase() +
    suffix.slice(1)
  );
}

/**
 * Converts classic Raycast hotkey encoding, e.g. `Shift-Control-Option-Command-0`,
 * into the Raycast Beta settings_v2 hotkey shape.
 * @param {string | null | undefined} value
 * @returns {BetaHotkey | null}
 */
function hotkey(value) {
  if (value == null) return null;
  const parts = String(value).split("-");
  const code = Number(parts.pop());
  if (!Number.isInteger(code))
    throw new Error(`invalid Raycast hotkey: ${value}`);
  const modifiers = parts.map((part) => {
    const modifier = modifierNames[part];
    if (!modifier) throw new Error(`invalid Raycast hotkey modifier: ${part}`);
    return { modifier };
  });
  return {
    kind: {
      type: "SingleStep",
      shortcut: { modifiers, key: { type: "LayoutIndependent", code } },
    },
    locality: "Global",
  };
}

/**
 * @param {WindowManagementConfig} config
 * @returns {BetaLayoutGroup[]}
 */
function configuredLayoutGroups(config) {
  const groups = config.layoutGroups ?? config.layouts ?? [];
  if (!Array.isArray(groups))
    throw new Error("Raycast Beta layoutGroups must be an array");
  return groups;
}

/**
 * @param {WindowManagementStore} windowManagement
 * @param {WindowManagementConfig} config
 * @returns {Promise<void>}
 */
async function applyLayoutGroups(windowManagement, config) {
  const groups = configuredLayoutGroups(config);
  if (groups.length === 0) return;

  const existingByName = new Map(
    (await windowManagement.list()).map((group) => [group.name, group]),
  );
  for (const group of groups) {
    if (!group || typeof group !== "object" || Array.isArray(group))
      throw new Error("invalid Raycast Beta layout group");
    if (typeof group.name !== "string" || group.name.trim() === "")
      throw new Error("Raycast Beta layout group missing name");
    if (!Array.isArray(group.layouts))
      throw new Error(
        `Raycast Beta layout group missing layouts: ${group.name}`,
      );

    const row = { ...group, name: group.name.trim() };
    const existing = group.id
      ? await windowManagement.getOne(group.id)
      : existingByName.get(row.name);
    if (existing) await windowManagement.updateOne(existing.id, row);
    else await windowManagement.save(row);
  }
}

/** @type {WindowManagementConfig} */
const config = JSON.parse(readFileSync(configPath, "utf8"));
const db = new data.DatabaseClient(supportDir, databasePassword, () => {});
try {
  const status = db.getDatabaseStatus();
  if (!status.allHealthy)
    throw new Error(
      `Raycast Beta database is not healthy: ${JSON.stringify(status)}`,
    );
  const settings = db.settings;
  await settings.sanityCheck();
  for (const row of await settings.allCommandSettingsForExtension(
    commandNamespace.betaExtensionId,
  )) {
    if (row.macosHotkey !== undefined)
      await settings.updateCommandSettings(row.id, {
        ...row,
        macosHotkey: null,
      });
  }
  for (const [classicId, value] of Object.entries(config.hotkeys ?? {})) {
    const id = betaCommandId(classicId);
    const row = {
      id,
      extensionId: commandNamespace.betaExtensionId,
      enabled: true,
      favorited: false,
      macosHotkey: hotkey(value),
    };
    if (await settings.getCommandSettings(id))
      await settings.updateCommandSettings(id, row);
    else await settings.addCommandSettings(row);
  }
  for (const classicId of config.disabledCommands ?? []) {
    const id = betaCommandId(classicId);
    const row = {
      id,
      extensionId: commandNamespace.betaExtensionId,
      enabled: false,
      favorited: false,
      macosHotkey: null,
    };
    if (await settings.getCommandSettings(id))
      await settings.updateCommandSettings(id, row);
    else await settings.addCommandSettings(row);
  }
  await applyLayoutGroups(db.windowManagement, config);
  await db.walCheckpointAll();
  console.error("info: Applied Raycast Beta window-management settings");
} finally {
  db.shutdown();
}
