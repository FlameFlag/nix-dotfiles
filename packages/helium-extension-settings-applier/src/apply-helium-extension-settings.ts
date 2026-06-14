#!/usr/bin/env bun
import { buildApplication, buildCommand, run, text_en } from "@stricli/core"
import { ClassicLevel } from "classic-level"
import LZString from "lz-string"

const refinedGitHubId = "hlepfoohegkhhmjieoechaddaejaokhf"

type ExtensionSettings = {
  readonly id: string
  readonly values: Record<string, unknown>
}

type ExtensionSettingsFile = {
  readonly local?: readonly ExtensionSettings[]
  readonly sync?: readonly ExtensionSettings[]
}

type RefinedGitHubOptions = Record<string, unknown> & {
  readonly personalToken?: string
}

const app = buildApplication(
  buildCommand<{
    readonly profileDir: string
    readonly settings: readonly string[]
    readonly ghToken: boolean
  }>({
    docs: {
      brief: "Apply Helium extension settings.",
      customUsage: [
        "--profile-dir <Default> --settings <settings.json> [--settings <settings.json> ...] [--gh-token]",
      ],
    },
    parameters: {
      flags: {
        profileDir: {
          kind: "parsed",
          parse: String,
          placeholder: "Default",
          brief: "Helium profile directory.",
        },
        settings: {
          kind: "parsed",
          parse: String,
          placeholder: "settings.json",
          variadic: true,
          brief: "Extension settings JSON file.",
        },
        ghToken: {
          kind: "boolean",
          default: false,
          brief: "Ask gh for an auth token and store it for Refined GitHub.",
        },
      },
    },
    func: async (flags) => {
      await flags.settings.reduce(
        (previous, settingsPath) =>
          previous.then(async () => {
            await applySettingsFile(
              flags.profileDir,
              (await Bun.file(settingsPath).json()) as ExtensionSettingsFile,
            )
          }),
        Promise.resolve(),
      )

      if (!flags.ghToken) return
      await setRefinedGitHubToken(flags.profileDir, githubToken())
    },
  }),
  {
    name: "apply-helium-extension-settings",
    scanner: {
      caseStyle: "allow-kebab-for-camel",
    },
    localization: {
      text: text_en,
    },
  },
)

await run(app, Bun.argv.slice(2), { process })

async function applySettingsFile(
  profileDir: string,
  settings: ExtensionSettingsFile,
) {
  await Promise.all([
    ...(settings.local ?? []).map((entry) =>
      writeStorageValues(
        profileDir,
        "Local Extension Settings",
        entry.id,
        entry.values,
      ),
    ),
    ...(settings.sync ?? []).map((entry) =>
      writeStorageValues(
        profileDir,
        "Sync Extension Settings",
        entry.id,
        entry.values,
      ),
    ),
  ])
}

async function writeStorageValues(
  profileDir: string,
  area: string,
  extensionId: string,
  values: Record<string, unknown>,
) {
  await withStorage(profileDir, area, extensionId, (db) =>
    db.batch(
      Object.entries(values).map(([key, value]) => ({
        type: "put",
        key,
        value: JSON.stringify(value),
      })),
    ),
  )
}

async function setRefinedGitHubToken(profileDir: string, token: string) {
  if (!token) return

  await withStorage(
    profileDir,
    "Sync Extension Settings",
    refinedGitHubId,
    async (db) => {
      await db.put(
        "options",
        JSON.stringify(
          LZString.compressToEncodedURIComponent(
            JSON.stringify({
              ...(await refinedGitHubOptions(db)),
              personalToken: token,
            }),
          ),
        ),
      )
    },
  )
}

async function refinedGitHubOptions(db: ClassicLevel<string, string>) {
  const raw = await db.get("options")
  if (!raw) return {}

  return JSON.parse(
    LZString.decompressFromEncodedURIComponent(JSON.parse(raw)) ?? "{}",
  ) as RefinedGitHubOptions
}

async function withStorage<T>(
  profileDir: string,
  area: string,
  extensionId: string,
  operation: (db: ClassicLevel<string, string>) => Promise<T>,
) {
  const db = new ClassicLevel<string, string>(
    `${profileDir}/${area}/${extensionId}`,
    {
      keyEncoding: "utf8",
      valueEncoding: "utf8",
      createIfMissing: true,
    },
  )
  await db.open()
  try {
    return await operation(db)
  } finally {
    await db.close()
  }
}

function githubToken() {
  const result = Bun.spawnSync(["gh", "auth", "token"], {
    stdout: "pipe",
    stderr: "pipe",
  })

  if (result.exitCode === 0)
    return new TextDecoder().decode(result.stdout).trim()

  console.error(
    "helium-browser: gh auth token failed; skipping Refined GitHub token setup",
  )
  return ""
}
