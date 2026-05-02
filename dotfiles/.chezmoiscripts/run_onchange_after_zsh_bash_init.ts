#!/usr/bin/env bun

import { join } from "pathe";
import type * as ChezmoiScript from "../.chezmoi-lib/script.ts";

const sourceDir = process.env.CHEZMOI_SOURCE_DIR;
if (!sourceDir) throw new Error("CHEZMOI_SOURCE_DIR is not set");
const script: typeof ChezmoiScript = await import(
  Bun.pathToFileURL(join(sourceDir, ".chezmoi-lib/script.ts")).href
);

type Shell = "zsh" | "bash";
type CommandArgs = readonly string[];
type ShellCommand = {
  readonly bin: string;
  readonly args: (shell: Shell) => CommandArgs;
};
type InitCommand = ShellCommand & {
  readonly dir: "atuin" | "starship" | "television" | "zoxide";
};
type CompletionCommand = ShellCommand & {
  readonly name:
    | "cargo"
    | "chezmoi"
    | "delta"
    | "deno"
    | "jj"
    | "nh"
    | "rustup"
    | "starship"
    | "tv"
    | "yazi"
    | "zellij";
};

const shells = ["zsh", "bash"] as const satisfies readonly Shell[];

const initCommands = [
  {
    bin: "starship",
    args: (shell) => ["init", shell],
    dir: "starship",
  },
  { bin: "zoxide", args: (shell) => ["init", shell], dir: "zoxide" },
  {
    bin: "atuin",
    args: (shell) => ["init", shell, "--disable-up-arrow"],
    dir: "atuin",
  },
  { bin: "tv", args: (shell) => ["init", shell], dir: "television" },
] as const satisfies readonly InitCommand[];

const completionCommands = [
  {
    bin: "chezmoi",
    args: (shell) => ["completion", shell],
    name: "chezmoi",
  },
  {
    bin: "jj",
    args: (shell) => ["util", "completion", shell],
    name: "jj",
  },
  {
    bin: "yazi",
    args: (shell) => ["--completions", shell],
    name: "yazi",
  },
  {
    bin: "zellij",
    args: (shell) => ["setup", "--generate-completion", shell],
    name: "zellij",
  },
  {
    bin: "starship",
    args: (shell) => ["completions", shell],
    name: "starship",
  },
  {
    bin: "deno",
    args: (shell) => ["completions", shell],
    name: "deno",
  },
  { bin: "nh", args: (shell) => ["completions", shell], name: "nh" },
  {
    bin: "delta",
    args: (shell) => ["--generate-completion", shell],
    name: "delta",
  },
  { bin: "tv", args: (shell) => ["completion", shell], name: "tv" },
  {
    bin: "rustup",
    args: (shell) => ["completions", shell],
    name: "rustup",
  },
  {
    bin: "rustup",
    args: (shell) => ["completions", shell, "cargo"],
    name: "cargo",
  },
] as const satisfies readonly CompletionCommand[];

async function generate() {
  const context = script.chezmoiContext();
  await Promise.all(
    [
      ".cache/starship",
      ".cache/zoxide",
      ".cache/atuin",
      ".cache/television",
      ".cache/zsh/completions",
      ".cache/bash/completions",
    ].map((path) => script.ensureDir(join(context.homeDir, path))),
  );

  await Promise.all(
    shells.flatMap((shell) =>
      initCommands
        .filter((command) => script.hasBin(command.bin))
        .map(async (command) =>
          script.writeCommandTextIfAvailable(
            command.bin,
            join(context.homeDir, ".cache", command.dir, `init.${shell}`),
            command.args(shell),
          ),
        ),
    ),
  );

  await Promise.all(
    shells.map(async (shell) => {
      const outdir = join(context.homeDir, ".cache", shell, "completions");
      const prefix = shell === "zsh" ? "_" : "";

      if (script.hasBin("atuin")) {
        await script.commandQuiet(
          script.commandArgs(
            "atuin",
            "gen-completions",
            "--shell",
            shell,
            "--out-dir",
            outdir,
          ),
        );
      }

      await Promise.all(
        (
          await Promise.all(
            completionCommands
              .filter((command) => script.hasBin(command.bin))
              .map(async (command) => ({
                command,
                result: await script.commandQuiet(
                  script.commandArgs(command.bin, ...command.args(shell)),
                ),
              })),
          )
        )
          .filter((completion) => completion.result.exitCode === 0)
          .map((completion) =>
            script.writeTextIfChanged(
              join(outdir, `${prefix}${completion.command.name}`),
              completion.result.stdout,
            ),
          ),
      );
    }),
  );
}

await generate();
