#!/usr/bin/env bun

import { cp, mkdtemp, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
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
const fetchTimeoutMs = 15_000;

function fetchWithTimeout(url: string | URL, init?: RequestInit) {
  return fetch(url, { ...init, signal: AbortSignal.timeout(fetchTimeoutMs) });
}

async function fetchLatestTag(repository: string) {
  const headers = new Headers({ Accept: "application/vnd.github+json" });
  if (process.env.GITHUB_TOKEN) {
    headers.set("Authorization", `Bearer ${process.env.GITHUB_TOKEN}`);
  }
  script.consola.info(`Fetching latest ${repository} release...`);
  const response = await fetchWithTimeout(
    `https://api.github.com/repos/${repository}/releases/latest`,
    { headers },
  );
  if (!response.ok) {
    throw new Error(
      `failed to fetch latest ${repository} release: ${response.status} ${response.statusText}`,
    );
  }
  const json = v.safeParse(githubReleaseSchema, await response.json());
  return json.success ? json.output.tag_name : undefined;
}

async function downloadText(url: string) {
  const response = await fetchWithTimeout(url);
  if (!response.ok) {
    throw new Error(`failed to download ${url}: ${response.status} ${response.statusText}`);
  }
  return await response.text();
}

async function downloadFile(url: string, path: string) {
  const response = await fetchWithTimeout(url);
  if (!response.ok) {
    throw new Error(`failed to download ${url}: ${response.status} ${response.statusText}`);
  }
  await Bun.write(path, response);
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
  const tempDir = await mkdtemp(join(tmpdir(), "catppuccin-zed-icons-"));
  const archivePath = join(tempDir, "zed-icons.tar.gz");

  try {
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
  } finally {
    await rm(tempDir, { force: true, recursive: true });
  }
}

const [themeTag, iconsTag] = await Promise.all([
  fetchLatestTag(repositories.theme),
  fetchLatestTag(repositories.icons),
]);
if (!themeTag) throw new Error("could not resolve latest Catppuccin Zed tag");
if (!iconsTag)
  throw new Error("could not resolve latest Catppuccin Zed Icons tag");
await installTheme(themeTag);
await installIcons(iconsTag);
