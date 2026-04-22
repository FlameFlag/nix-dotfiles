#!/usr/bin/env bun

import { join } from "pathe";
import type * as ChezmoiScript from "../.chezmoi-lib/script.ts";

const sourceDir = process.env.CHEZMOI_SOURCE_DIR;
if (!sourceDir) throw new Error("CHEZMOI_SOURCE_DIR is not set");
const script: typeof ChezmoiScript = await import(
  Bun.pathToFileURL(join(sourceDir, ".chezmoi-lib/script.ts")).href
);

async function generate() {
  const context = script.chezmoiContext();
  await Promise.all([
    script.ensureDir(join(context.homeDir, ".cache/starship")),
    script.ensureDir(join(context.homeDir, ".cache/zoxide")),
    script.ensureDir(join(context.homeDir, ".local/share/atuin")),
  ]);

  await script.writeCommandTextIfAvailable(
    "starship",
    join(context.homeDir, ".cache/starship/init.nu"),
    ["init", "nu"],
  );
  await script.writeCommandTextIfAvailable(
    "zoxide",
    join(context.homeDir, ".cache/zoxide/init.nu"),
    ["init", "nushell"],
  );
  await script.writeCommandTextIfAvailable(
    "atuin",
    join(context.homeDir, ".local/share/atuin/init.nu"),
    ["init", "nu", "--disable-up-arrow"],
  );

  const atuinInit = join(context.homeDir, ".local/share/atuin/init.nu");
  const file = Bun.file(atuinInit);
  if (await file.exists()) {
    await script.writeTextIfChanged(
      atuinInit,
      (await file.text()).replaceAll("$cmd e>| complete", "$cmd | complete"),
    );
  }
}

await generate();
