import { execa } from "execa";

export type CommandArgs = readonly [string, ...string[]];
export type CommandOutput = {
  exitCode: number;
  stderr: string;
  stdout: string;
};

export function commandArgs(bin: string, ...args: string[]): CommandArgs {
  if (!bin) {
    throw new Error("command binary is empty");
  }
  return [bin, ...args];
}

export function hasBin(bin: string) {
  return Bun.which(bin) !== null;
}

export async function command(args: CommandArgs) {
  const [file, ...commandArgs] = args;
  return await execa(file, commandArgs, { stdio: "inherit" });
}

export async function commandText(args: CommandArgs) {
  const [file, ...commandArgs] = args;
  return (await execa(file, commandArgs, { stripFinalNewline: false })).stdout;
}

export async function commandTextOr(args: CommandArgs, fallback = "") {
  const result = await commandQuiet(args);
  return result.exitCode === 0 ? result.stdout : fallback;
}

export async function commandQuiet(args: CommandArgs) {
  const [file, ...commandArgs] = args;
  return await execa(file, commandArgs, {
    reject: false,
    stripFinalNewline: false,
  });
}

export async function commandWithInput(
  args: CommandArgs,
  input: string,
  timeoutMs?: number,
) {
  const [file, ...commandArgs] = args;
  return await execa(file, commandArgs, {
    input,
    stripFinalNewline: false,
    timeout: timeoutMs,
  });
}
