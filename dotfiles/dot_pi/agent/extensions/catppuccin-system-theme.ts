import { execa } from "execa";

const darkTheme = "catppuccin-frappe";
const lightTheme = "catppuccin-latte";
type Theme = typeof darkTheme | typeof lightTheme;

type PiContext = {
  ui: {
    setTheme(theme: Theme): void;
  };
};

type ExtensionAPI = {
  on(
    event: "session_start",
    handler: (event: unknown, ctx: PiContext) => void | Promise<void>,
  ): void;
  on(event: "session_shutdown", handler: () => void): void;
};

async function commandSucceeds(
  file: string,
  args: readonly string[] = [],
): Promise<boolean> {
  const result = await execa(file, args, { reject: false });
  return result.exitCode === 0;
}

async function isDarwinDarkMode(): Promise<boolean> {
  return await commandSucceeds("defaults", [
    "read",
    "-g",
    "AppleInterfaceStyle",
  ]);
}

async function isGnomeDarkMode(): Promise<boolean> {
  const result = await execa(
    "gsettings",
    ["get", "org.gnome.desktop.interface", "color-scheme"],
    { reject: false },
  );
  return result.exitCode === 0
    ? result.stdout.toLowerCase().includes("dark")
    : true;
}

async function isDarkMode(): Promise<boolean> {
  return process.platform === "darwin"
    ? await isDarwinDarkMode()
    : await isGnomeDarkMode();
}

async function systemTheme(): Promise<Theme> {
  return (await isDarkMode()) ? darkTheme : lightTheme;
}

export default function (pi: ExtensionAPI) {
  let intervalId: ReturnType<typeof setInterval> | null = null;

  pi.on("session_start", async (_event, ctx) => {
    let currentTheme = await systemTheme();
    ctx.ui.setTheme(currentTheme);

    intervalId = setInterval(async () => {
      const nextTheme = await systemTheme();
      if (nextTheme !== currentTheme) {
        currentTheme = nextTheme;
        ctx.ui.setTheme(currentTheme);
      }
    }, 2000);
  });

  pi.on("session_shutdown", () => {
    if (intervalId) {
      clearInterval(intervalId);
      intervalId = null;
    }
  });
}
