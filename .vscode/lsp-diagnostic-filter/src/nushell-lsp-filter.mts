#!/usr/bin/env node
import { spawn } from "node:child_process";
import process from "node:process";

import {
  createDiagnosticFilter,
  createLspFilter,
  isTemplateUri,
  relayChildProcess,
} from "./lsp-diagnostic-filter.mjs";

const realNu = process.env.NU_LSP_REAL_NU || "nu";
const args = process.argv.slice(2);

function main(): void {
  if (!args.includes("--lsp")) {
    relayChildProcess(spawn(realNu, args, { stdio: "inherit" }), realNu);
    return;
  }

  const child = spawn(realNu, args, { stdio: ["pipe", "pipe", "pipe"] });

  process.stdin.pipe(child.stdin);
  child.stderr.pipe(process.stderr);
  child.stdout.on("data", createLspFilter(createDiagnosticFilter(isTemplateUri)));

  relayChildProcess(child, realNu);
}

main();
