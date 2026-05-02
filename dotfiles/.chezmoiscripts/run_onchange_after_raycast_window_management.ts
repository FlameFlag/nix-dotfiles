#!/usr/bin/env bun

import { join } from "pathe";
import type * as ChezmoiScript from "../.chezmoi-lib/script.ts";

const sourceDir = process.env.CHEZMOI_SOURCE_DIR;
if (!sourceDir) throw new Error("CHEZMOI_SOURCE_DIR is not set");
const script: typeof ChezmoiScript = await import(
  Bun.pathToFileURL(join(sourceDir, ".chezmoi-lib/script.ts")).href
);

const domain = "com.raycast.macos";
const raycastBin = "/Applications/Raycast.app/Contents/MacOS/Raycast";

type RaycastPaths = {
  config: string;
  db: string;
  sqlHelper: string;
};

function escapeRegExp(value: string) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

async function arrayContains(key: string, value: string) {
  const output = await script.commandTextOr(
    script.commandArgs("defaults", "read", domain, key),
  );
  const linePattern = new RegExp(`^\\s*"?${escapeRegExp(value)}"?,\\s*$`);
  return output.split(/\r?\n/).some((line) => linePattern.test(line));
}

async function arrayAddOnce(key: string, value: string) {
  if (await arrayContains(key, value)) return;
  await script.command(
    script.commandArgs("defaults", "write", domain, key, "-array-add", value),
  );
}

async function extractSalt() {
  const lines = (
    await script.commandText(script.commandArgs("strings", "-a", raycastBin))
  ).split(/\r?\n/);
  return lines.find(
    (line, index) =>
      lines[index - 1] === "copyDatabaseEncryptionPassphraseToClipboard()" &&
      /^[!-~]{32}$/.test(line),
  );
}

async function quitRaycastIfRunning() {
  if (
    (await script.commandQuiet(script.commandArgs("pgrep", "-qx", "Raycast")))
      .exitCode !== 0
  )
    return false;
  await script.commandQuiet(
    script.commandArgs("osascript", "-e", 'tell application "Raycast" to quit'),
  );
  await waitForRaycastToQuit();
  return true;
}

async function waitForRaycastToQuit(attempt = 0): Promise<void> {
  if (attempt >= 30) {
    throw new Error("Timed out waiting for Raycast to quit");
  }
  const stillRunning = await script.commandQuiet(
    script.commandArgs("pgrep", "-qx", "Raycast"),
  );
  if (stillRunning.exitCode !== 0) return;
  await Bun.sleep(200);
  await waitForRaycastToQuit(attempt + 1);
}

async function ensureRaycastDefaults() {
  await arrayAddOnce("onboarding_completedTaskIdentifiers", "windowManagement");
  await arrayAddOnce(
    "commandsPreferencesExpandedItemIds",
    "builtin_package_windowManagement",
  );
}

function raycastPaths(): RaycastPaths {
  const context = script.chezmoiContext();
  return {
    config: join(
      context.sourceDir,
      "dot_config/raycast/window-management.json",
    ),
    db: join(
      context.homeDir,
      "Library/Application Support/com.raycast.macos/raycast-enc.sqlite",
    ),
    sqlHelper: join(
      context.sourceDir,
      ".chezmoitemplates/raycast_window_management_sql.py",
    ),
  };
}

async function fileExists(path: string, missingMessage: string) {
  if (await Bun.file(path).exists()) return true;
  script.consola.warn(missingMessage);
  return false;
}

async function canApplyConfig({ config, db }: RaycastPaths) {
  const hasConfig = await fileExists(
    config,
    `Raycast window-management config not found: ${config}`,
  );
  const hasDb = await fileExists(db, `Raycast database not found: ${db}`);
  return hasConfig && hasDb;
}

async function assertRaycastInstalled() {
  if (await Bun.file(raycastBin).exists()) return;
  throw new Error(`Raycast binary not found: ${raycastBin}`);
}

async function databaseKey() {
  const databaseKey = (
    await script.commandTextOr(
      script.commandArgs(
        "security",
        "find-generic-password",
        "-s",
        "Raycast",
        "-a",
        "database_key",
        "-w",
      ),
    )
  ).trim();
  if (!databaseKey)
    throw new Error("Raycast database key not found in Keychain");
  return databaseKey;
}

async function databasePassword() {
  const key = await databaseKey();
  const salt = await extractSalt();
  if (!salt)
    throw new Error(
      `Could not extract Raycast database salt from ${raycastBin}`,
    );
  return script.sha256Text(`${key}${salt}`);
}

async function applyConfig(paths: RaycastPaths) {
  script.consola.info("Applying Raycast window-management settings...");
  await script.commandWithInput(
    script.commandArgs(paths.sqlHelper, paths.db, paths.config),
    await databasePassword(),
    20_000,
  );
}

function warningMessage(error: unknown) {
  return error instanceof Error
    ? error.message
    : "Timed out applying Raycast window-management settings";
}

async function tryApplyConfig(paths: RaycastPaths) {
  try {
    await applyConfig(paths);
  } catch (error) {
    script.consola.warn(warningMessage(error));
  }
}

async function restartRaycastIfNeeded(wasRunning: boolean) {
  if (!wasRunning) return;
  await script.commandQuiet(script.commandArgs("open", "-ga", "Raycast"));
}

async function generate() {
  await ensureRaycastDefaults();
  const paths = raycastPaths();
  if (!(await canApplyConfig(paths))) return;
  await assertRaycastInstalled();

  const wasRunning = await quitRaycastIfRunning();
  await tryApplyConfig(paths);
  await restartRaycastIfNeeded(wasRunning);
}

if (script.chezmoiContext().os === "darwin") {
  await generate();
}
