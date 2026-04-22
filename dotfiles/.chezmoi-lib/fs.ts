import { mkdir } from "node:fs/promises";
import { dirname } from "pathe";
import { commandArgs, commandText, hasBin } from "./command.ts";

export async function ensureDir(path: string) {
  await mkdir(path, { recursive: true });
}

export async function writeTextIfChanged(path: string, contents: string) {
  const file = Bun.file(path);
  if (await file.exists()) {
    const current = await file.text();
    if (current === contents) return false;
  }
  await ensureDir(dirname(path));
  await Bun.write(path, contents);
  return true;
}

export async function writeCommandTextIfAvailable(
  bin: string,
  path: string,
  args: readonly string[],
) {
  if (!hasBin(bin)) return false;
  return await writeTextIfChanged(
    path,
    await commandText(commandArgs(bin, ...args)),
  );
}
