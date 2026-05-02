#!/usr/bin/env bun

import { cp, rm } from "node:fs/promises";
import ky from "ky";
import { join } from "pathe";
import * as v from "valibot";
import type * as ChezmoiScript from "../.chezmoi-lib/script.ts";

const sourceDir = process.env.CHEZMOI_SOURCE_DIR;
if (!sourceDir) throw new Error("CHEZMOI_SOURCE_DIR is not set");
const script: typeof ChezmoiScript = await import(
  Bun.pathToFileURL(join(sourceDir, ".chezmoi-lib/script.ts")).href
);

const repositories = {
  theme: "catppuccin/zed",
  icons: "catppuccin/zed-icons",
} as const;
const themeFile = "catppuccin-pink.json";
const githubReleaseSchema = v.object({ tag_name: v.string() });
const http = ky.create({
  headers: process.env.GITHUB_TOKEN
    ? { Authorization: `Bearer ${process.env.GITHUB_TOKEN}` }
    : undefined,
  timeout: 15_000,
});

async function fetchLatestTag(repository: string) {
  script.consola.info(`Fetching latest ${repository} release...`);
  return v.parse(
    githubReleaseSchema,
    await http
      .get(`https://api.github.com/repos/${repository}/releases/latest`, {
        headers: { Accept: "application/vnd.github+json" },
      })
      .json<unknown>(),
  ).tag_name;
}

async function downloadText(url: string) {
  return await http.get(url).text();
}

async function downloadFile(url: string, path: string) {
  await Bun.write(path, await http.get(url).blob());
}

async function installTheme(latestTag: string) {
  const context = script.chezmoiContext();
  const themePath = join(context.homeDir, ".config/zed/themes", themeFile);
  script.consola.info(`Downloading ${themeFile}...`);
  await script.ensureDir(join(context.homeDir, ".config/zed/themes"));
  if (
    await script.writeTextIfChanged(
      themePath,
      await downloadText(
        `https://github.com/${repositories.theme}/releases/download/${latestTag}/${themeFile}`,
      ),
    )
  ) {
    script.consola.success(`Theme installed to ${themePath}`);
  }
}

async function installIcons(latestTag: string) {
  const context = script.chezmoiContext();
  const zedConfigDir = join(context.homeDir, ".config/zed");

  await script.withTempDir(async (tempDir) => {
    const archivePath = join(tempDir, "zed-icons.tar.gz");
    script.consola.info("Downloading Catppuccin Zed icon theme...");
    await downloadFile(
      `https://codeload.github.com/${repositories.icons}/tar.gz/${latestTag}`,
      archivePath,
    );
    await script.command([
      "tar",
      "-xzf",
      archivePath,
      "-C",
      tempDir,
      "--strip-components=1",
    ]);

    await script.ensureDir(join(zedConfigDir, "icon_themes"));
    await rm(join(zedConfigDir, "icons"), { force: true, recursive: true });
    await cp(
      join(tempDir, "icon_themes", "catppuccin-icons.json"),
      join(zedConfigDir, "icon_themes", "catppuccin-icons.json"),
    );
    await cp(join(tempDir, "icons"), join(zedConfigDir, "icons"), {
      recursive: true,
    });
    script.consola.success(`Icon theme installed to ${zedConfigDir}`);
  });
}

const [themeTag, iconsTag] = await Promise.all([
  fetchLatestTag(repositories.theme),
  fetchLatestTag(repositories.icons),
]);
await installTheme(themeTag);
await installIcons(iconsTag);
