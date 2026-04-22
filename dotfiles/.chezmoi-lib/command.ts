import { $ } from "bun";

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
  return await $`${args}`;
}

export async function commandText(args: CommandArgs) {
  return await $`${args}`.text();
}

export async function commandTextOr(args: CommandArgs, fallback = "") {
  const result = await commandQuiet(args);
  return result.exitCode === 0 ? result.stdout.toString() : fallback;
}

export async function commandQuiet(args: CommandArgs) {
  return await $`${args}`.quiet().nothrow();
}

export async function commandWithInput(
  args: CommandArgs,
  input: string,
  timeoutMs?: number,
) {
  const proc = Bun.spawn([...args], {
    stdin: "pipe",
    stdout: "pipe",
    stderr: "pipe",
  });
  proc.stdin.write(input);
  proc.stdin.end();

  let timeout: Timer | undefined;
  const exited =
    timeoutMs === undefined
      ? proc.exited
      : Promise.race([
          proc.exited,
          new Promise<number>((_, reject) => {
            timeout = setTimeout(() => {
              proc.kill();
              reject(
                new Error(`${args.join(" ")} timed out after ${timeoutMs}ms`),
              );
            }, timeoutMs);
          }),
        ]);

  const [exitCode, stdout, stderr] = await Promise.all([
    exited.finally(() => {
      if (timeout) clearTimeout(timeout);
    }),
    new Response(proc.stdout).text(),
    new Response(proc.stderr).text(),
  ]);
  if (exitCode !== 0) {
    throw new Error(
      `${args.join(" ")} failed with exit code ${exitCode}: ${stderr.trim()}`,
    );
  }
  return { exitCode, stderr, stdout };
}
