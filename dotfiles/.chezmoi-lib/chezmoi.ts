import type { ReporterOptions } from "envalid";
import { bool, cleanEnv, makeValidator, str } from "envalid";
import type { LiteralUnion, Tagged } from "type-fest";

export type NonEmptyString = Tagged<string, "NonEmptyString">;

export type ChezmoiArch = LiteralUnion<
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
  | "wasm",
  string
>;

export type ChezmoiCommand = LiteralUnion<
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
  | "verify",
  string
>;

export type ChezmoiOs = LiteralUnion<
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
  | "windows",
  string
>;

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
type ParsedChezmoiEnv = ReturnType<typeof parseChezmoiEnv>;

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

const safeInteger = makeValidator<number>((value) => {
  const number = Number(value);
  if (!Number.isSafeInteger(number)) {
    throw new Error(`Invalid safe integer: "${value}"`);
  }
  return number;
});

function throwReporter<T>({ errors }: ReporterOptions<T>) {
  const messages = Object.entries(errors).map(
    ([name, error]) =>
      `${name}: ${error instanceof Error ? error.message : "invalid value"}`,
  );
  if (messages.length > 0) {
    throw new Error(messages.join("\n"));
  }
}

function chezmoiOS(): ChezmoiOs {
  const value = process.env.CHEZMOI_OS;
  if (value) return value;
  return process.platform === "win32" ? "windows" : process.platform;
}

function parseChezmoiEnv() {
  return cleanEnv(
    process.env,
    {
      CHEZMOI: bool({ default: false }),
      CHEZMOI_ARCH: str({ default: undefined }),
      CHEZMOI_CACHE_DIR: str({ default: undefined }),
      CHEZMOI_COMMAND: str({ default: undefined }),
      CHEZMOI_COMMAND_DIR: str({ default: undefined }),
      CHEZMOI_CONFIG_FILE: str({ default: undefined }),
      CHEZMOI_DEST_DIR: str({ default: undefined }),
      CHEZMOI_EXECUTABLE: str({ default: undefined }),
      CHEZMOI_GID: safeInteger({ default: undefined }),
      CHEZMOI_GROUP: str({ default: undefined }),
      CHEZMOI_HOME_DIR: str({ default: undefined }),
      CHEZMOI_NO_PAGER: bool({ default: false }),
      CHEZMOI_OS: str({ default: undefined }),
      CHEZMOI_RAW_HOME_DIR: str({ default: undefined }),
      CHEZMOI_SOURCE_DIR: str(),
      CHEZMOI_SOURCE_FILE: str(),
      CHEZMOI_UID: safeInteger({ default: undefined }),
      CHEZMOI_USERNAME: str({ default: undefined }),
      CHEZMOI_VERBOSE: bool({ default: false }),
      CHEZMOI_VERSION_VERSION: str({ default: undefined }),
      CHEZMOI_WORKING_TREE: str({ default: undefined }),
      HOME: str(),
    },
    { reporter: throwReporter },
  );
}

function envOrHome(value: string | undefined, homeDir: string) {
  return value ?? homeDir;
}

function contextFromEnv(parsedEnv: ParsedChezmoiEnv): ChezmoiContext {
  const homeDir = envOrHome(parsedEnv.CHEZMOI_HOME_DIR, parsedEnv.HOME);
  const sourceDir = parsedEnv.CHEZMOI_SOURCE_DIR;
  return {
    arch: parsedEnv.CHEZMOI_ARCH as ChezmoiArch | undefined,
    cacheDir: parsedEnv.CHEZMOI_CACHE_DIR,
    command: parsedEnv.CHEZMOI_COMMAND as ChezmoiCommand | undefined,
    commandDir: parsedEnv.CHEZMOI_COMMAND_DIR,
    configFile: parsedEnv.CHEZMOI_CONFIG_FILE,
    destDir: parsedEnv.CHEZMOI_DEST_DIR ?? homeDir,
    executable: parsedEnv.CHEZMOI_EXECUTABLE,
    gid: parsedEnv.CHEZMOI_GID,
    group: parsedEnv.CHEZMOI_GROUP,
    homeDir,
    isChezmoi: parsedEnv.CHEZMOI,
    noPager: parsedEnv.CHEZMOI_NO_PAGER,
    sourceFile: parsedEnv.CHEZMOI_SOURCE_FILE,
    sourceDir,
    os: chezmoiOS(),
    rawHomeDir: parsedEnv.CHEZMOI_RAW_HOME_DIR ?? homeDir,
    uid: parsedEnv.CHEZMOI_UID,
    username: parsedEnv.CHEZMOI_USERNAME,
    verbose: parsedEnv.CHEZMOI_VERBOSE,
    version: parsedEnv.CHEZMOI_VERSION_VERSION,
    workingTree: envOrHome(parsedEnv.CHEZMOI_WORKING_TREE, sourceDir),
  };
}

export function chezmoiContext(): ChezmoiContext {
  return contextFromEnv(parseChezmoiEnv());
}
