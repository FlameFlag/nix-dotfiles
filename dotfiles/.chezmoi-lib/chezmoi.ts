export type NonEmptyString = string & {
  readonly __nonEmptyString: unique symbol;
};

export type ChezmoiArch =
  | "386"
  | "amd64"
  | "arm"
  | "arm64"
  | "loong64"
  | "mips"
  | "mips64"
  | "mips64le"
  | "mipsle"
  | "ppc64"
  | "ppc64le"
  | "riscv64"
  | "s390x"
  | "wasm"
  | (string & {});

export type ChezmoiCommand =
  | "add"
  | "apply"
  | "cat"
  | "cd"
  | "chattr"
  | "destroy"
  | "diff"
  | "edit"
  | "execute-template"
  | "forget"
  | "git"
  | "ignored"
  | "import"
  | "init"
  | "merge"
  | "managed"
  | "purge"
  | "re-add"
  | "source-path"
  | "status"
  | "target-path"
  | "unmanaged"
  | "update"
  | "verify"
  | (string & {});

export type ChezmoiOs =
  | "aix"
  | "android"
  | "darwin"
  | "dragonfly"
  | "freebsd"
  | "illumos"
  | "ios"
  | "js"
  | "linux"
  | "netbsd"
  | "openbsd"
  | "plan9"
  | "solaris"
  | "wasip1"
  | "windows"
  | (string & {});

type ChezmoiEnvName =
  | "CHEZMOI"
  | "CHEZMOI_ARCH"
  | "CHEZMOI_ARGS"
  | "CHEZMOI_CACHE_DIR"
  | "CHEZMOI_COMMAND"
  | "CHEZMOI_COMMAND_DIR"
  | "CHEZMOI_CONFIG_FILE"
  | "CHEZMOI_DEST_DIR"
  | "CHEZMOI_EXECUTABLE"
  | "CHEZMOI_GID"
  | "CHEZMOI_GROUP"
  | "CHEZMOI_HOME_DIR"
  | "CHEZMOI_NO_PAGER"
  | "CHEZMOI_OS"
  | "CHEZMOI_RAW_HOME_DIR"
  | "CHEZMOI_SOURCE_DIR"
  | "CHEZMOI_SOURCE_FILE"
  | "CHEZMOI_UID"
  | "CHEZMOI_USERNAME"
  | "CHEZMOI_VERBOSE"
  | "CHEZMOI_VERSION_VERSION"
  | "CHEZMOI_WORKING_TREE";
type EnvName = ChezmoiEnvName | "HOME";

export type ChezmoiContext = {
  arch: ChezmoiArch | undefined;
  cacheDir: string | undefined;
  command: ChezmoiCommand | undefined;
  commandDir: string | undefined;
  configFile: string | undefined;
  destDir: string;
  executable: string | undefined;
  gid: number | undefined;
  group: string | undefined;
  sourceDir: string;
  sourceFile: string;
  homeDir: string;
  isChezmoi: boolean;
  noPager: boolean;
  os: ChezmoiOs;
  rawHomeDir: string;
  uid: number | undefined;
  username: string | undefined;
  verbose: boolean;
  version: string | undefined;
  workingTree: string;
};

export function env(name: EnvName): NonEmptyString {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is not set`);
  }
  return value as NonEmptyString;
}

function chezmoiOS(): ChezmoiOs {
  const value = process.env.CHEZMOI_OS;
  if (value) return value;
  return process.platform === "win32" ? "windows" : process.platform;
}

function booleanEnv(name: ChezmoiEnvName) {
  const value = process.env[name]?.toLowerCase();
  return value === "1" || value === "true";
}

function optionalEnv(name: EnvName): string | undefined {
  return process.env[name];
}

function numberEnv(name: ChezmoiEnvName): number | undefined {
  const value = process.env[name];
  if (!value) return undefined;
  const number = Number(value);
  return Number.isSafeInteger(number) ? number : undefined;
}

export function chezmoiContext(): ChezmoiContext {
  const sourceDir = env("CHEZMOI_SOURCE_DIR");
  const homeDir = process.env.CHEZMOI_HOME_DIR ?? env("HOME");
  return {
    arch: optionalEnv("CHEZMOI_ARCH") as ChezmoiArch | undefined,
    cacheDir: optionalEnv("CHEZMOI_CACHE_DIR"),
    command: optionalEnv("CHEZMOI_COMMAND") as ChezmoiCommand | undefined,
    commandDir: optionalEnv("CHEZMOI_COMMAND_DIR"),
    configFile: optionalEnv("CHEZMOI_CONFIG_FILE"),
    destDir: process.env.CHEZMOI_DEST_DIR ?? homeDir,
    executable: optionalEnv("CHEZMOI_EXECUTABLE"),
    gid: numberEnv("CHEZMOI_GID"),
    group: optionalEnv("CHEZMOI_GROUP"),
    homeDir,
    isChezmoi: booleanEnv("CHEZMOI"),
    noPager: booleanEnv("CHEZMOI_NO_PAGER"),
    sourceFile: env("CHEZMOI_SOURCE_FILE"),
    sourceDir,
    os: chezmoiOS(),
    rawHomeDir: process.env.CHEZMOI_RAW_HOME_DIR ?? homeDir,
    uid: numberEnv("CHEZMOI_UID"),
    username: optionalEnv("CHEZMOI_USERNAME"),
    verbose: booleanEnv("CHEZMOI_VERBOSE"),
    version: optionalEnv("CHEZMOI_VERSION_VERSION"),
    workingTree: process.env.CHEZMOI_WORKING_TREE ?? sourceDir,
  };
}
