#!/usr/bin/env bun

import pLimit from "p-limit";
import { join } from "pathe";
import type * as ChezmoiScript from "../.chezmoi-lib/script.ts";

const sourceDir = process.env.CHEZMOI_SOURCE_DIR;
if (!sourceDir) throw new Error("CHEZMOI_SOURCE_DIR is not set");
const script: typeof ChezmoiScript = await import(
  Bun.pathToFileURL(join(sourceDir, ".chezmoi-lib/script.ts")).href
);

async function installedExtensions() {
  if (!script.hasBin("code")) return [];
  const output = await script.commandTextOr(
    script.commandArgs("code", "--list-extensions"),
  );
  return output
    .split(/\r?\n/)
    .map((line) => line.trim().toLowerCase())
    .filter(Boolean)
    .sort();
}

async function generate() {
  if (!script.hasBin("code")) return;
  const file = Bun.file(
    join(
      script.chezmoiContext().sourceDir,
      "dot_config/Code/User/vscode-extensions.txt",
    ),
  );
  if (!(await file.exists())) return;
  const installed = new Set(await installedExtensions());

  const limit = pLimit(2);
  await Promise.all(
    (await file.text())
      .split(/\r?\n/)
      .map((line) => line.trim())
      .filter((line) => line && !installed.has(line.toLowerCase()))
      .map((extension) =>
        limit(() =>
          script.command(
            script.commandArgs(
              "code",
              "--install-extension",
              extension,
              "--force",
            ),
          ),
        ),
      ),
  );
}

await generate();
