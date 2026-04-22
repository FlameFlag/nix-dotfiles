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

async function generate() {
  const context = script.chezmoiContext();
  const config = join(
    context.sourceDir,
    "dot_config/raycast/window-management.json",
  );
  const db = join(
    context.homeDir,
    "Library/Application Support/com.raycast.macos/raycast-enc.sqlite",
  );
  const sqlHelper = join(
    context.sourceDir,
    ".chezmoitemplates/raycast_window_management_sql.py",
  );

  await arrayAddOnce("onboarding_completedTaskIdentifiers", "windowManagement");
  await arrayAddOnce(
    "commandsPreferencesExpandedItemIds",
    "builtin_package_windowManagement",
  );

  if (!(await Bun.file(config).exists())) {
    script.consola.warn(
      `Raycast window-management config not found: ${config}`,
    );
    return;
  }
  if (!(await Bun.file(db).exists())) {
    script.consola.warn(`Raycast database not found: ${db}`);
    return;
  }
  if (!(await Bun.file(raycastBin).exists())) {
    throw new Error(`Raycast binary not found: ${raycastBin}`);
  }

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

  const salt = await extractSalt();
  if (!salt)
    throw new Error(
      `Could not extract Raycast database salt from ${raycastBin}`,
    );

  const wasRunning = await quitRaycastIfRunning();
  script.consola.info("Applying Raycast window-management settings...");
  try {
    await script.commandWithInput(
      script.commandArgs(sqlHelper, db, config),
      script.sha256Text(`${databaseKey}${salt}`),
      20_000,
    );
  } catch (error) {
    script.consola.warn(
      error instanceof Error
        ? error.message
        : "Timed out applying Raycast window-management settings",
    );
  }
  if (wasRunning) {
    await script.commandQuiet(script.commandArgs("open", "-ga", "Raycast"));
  }
}

if (script.chezmoiContext().os === "darwin") {
  await generate();
}
