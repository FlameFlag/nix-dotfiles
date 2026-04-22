#!/usr/bin/env bun

import { cp, rm } from "node:fs/promises";
import { join } from "pathe";
import type * as ChezmoiScript from "../.chezmoi-lib/script.ts";

const sourceDir = process.env.CHEZMOI_SOURCE_DIR;
if (!sourceDir) throw new Error("CHEZMOI_SOURCE_DIR is not set");
const script: typeof ChezmoiScript = await import(
  Bun.pathToFileURL(join(sourceDir, ".chezmoi-lib/script.ts")).href
);

const yaziPluginsRepo = "https://github.com/yazi-rs/plugins.git";
const officialPlugins = [
  "diff",
  "full-border",
  "smart-enter",
  "smart-paste",
  "git",
] as const;
const externalPlugins = {
  "system-clipboard": "https://github.com/orhnk/system-clipboard.yazi.git",
  starship: "https://github.com/Rolv-Apneseth/starship.yazi.git",
} as const;
type OfficialPlugin = (typeof officialPlugins)[number];
type ExternalPluginName = keyof typeof externalPlugins;

async function installPluginLocal(
  pluginName: OfficialPlugin,
  tempPluginsDir: string,
  pluginsDir: string,
) {
  const pluginDir = join(pluginsDir, `${pluginName}.yazi`);
  await rm(pluginDir, { force: true, recursive: true });
  script.consola.info(`Installing plugin ${pluginName}...`);
  await cp(join(tempPluginsDir, `${pluginName}.yazi`), pluginDir, {
    recursive: true,
  });
}

async function installPlugin(
  pluginName: ExternalPluginName,
  repoUrl: (typeof externalPlugins)[ExternalPluginName],
  pluginsDir: string,
) {
  const pluginDir = join(pluginsDir, `${pluginName}.yazi`);
  await rm(pluginDir, { force: true, recursive: true });
  script.consola.info(`Installing plugin ${pluginName}...`);
  await script.command(
    script.commandArgs(
      "git",
      "clone",
      "--depth",
      "1",
      "--single-branch",
      "--no-tags",
      "--quiet",
      repoUrl,
      pluginDir,
    ),
  );
  await rm(join(pluginDir, ".git"), { force: true, recursive: true });
}

async function generate() {
  if (!script.hasBin("git")) {
    throw new Error("git not found on PATH");
  }

  const context = script.chezmoiContext();
  const configDir = join(context.homeDir, ".config/yazi");
  const pluginsDir = join(configDir, "plugins");
  const flavorsDir = join(configDir, "flavors");
  await Promise.all([
    script.ensureDir(pluginsDir),
    script.ensureDir(flavorsDir),
  ]);

  await script.withTempDir(async (tempPluginsDir) => {
    script.consola.info("Downloading plugins repository...");
    await script.command(
      script.commandArgs(
        "git",
        "clone",
        "--depth",
        "1",
        "--single-branch",
        "--no-tags",
        "--quiet",
        yaziPluginsRepo,
        tempPluginsDir,
      ),
    );
    await rm(join(tempPluginsDir, ".git"), { force: true, recursive: true });

    await Promise.all([
      ...officialPlugins.map((plugin) =>
        installPluginLocal(plugin, tempPluginsDir, pluginsDir),
      ),
      ...script
        .entriesOf(externalPlugins)
        .map((plugin) => installPlugin(plugin[0], plugin[1], pluginsDir)),
    ]);
    script.consola.success("Yazi plugins installed");
  });
}

await generate();
