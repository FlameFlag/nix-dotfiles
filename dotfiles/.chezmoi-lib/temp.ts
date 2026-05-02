import { temporaryDirectoryTask } from "tempy";

export async function withTempDir<T>(
  fn: (path: string) => Promise<T>,
): Promise<T> {
  return await temporaryDirectoryTask(fn, { prefix: "chezmoi-script-" });
}
