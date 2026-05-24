<h1 align="center">nix-dotfiles</h1>

<p align="center">
  <b>
    My Nix and chezmoi setup for getting a machine back to feeling like mine
    without spending a whole weekend on it
  </b>
</p>

<p align="center">
  <a href="#repo-map">Repo map</a>
  ·
  <a href="#system-flow">System flow</a>
  ·
  <a href="#bootstrap">Bootstrap</a>
  ·
  <a href="#system-builds">System builds</a>
  ·
  <a href="#smoke-tests">Smoke tests</a>
</p>

<p align="center">
  <a href="https://nixos.org">
    <img alt="NixOS" src="https://img.shields.io/badge/NixOS-303446?style=for-the-badge&logo=nixos&logoColor=c6d0f5&labelColor=232634">
  </a>
  <a href="https://github.com/nix-darwin/nix-darwin">
    <img alt="nix-darwin" src="https://img.shields.io/badge/nix--darwin-8caaee?style=for-the-badge&logo=apple&logoColor=232634&labelColor=c6d0f5">
  </a>
  <a href="https://www.chezmoi.io/">
    <img alt="chezmoi" src="https://img.shields.io/badge/chezmoi-a6d189?style=for-the-badge&logo=homeassistant&logoColor=232634&labelColor=414559">
  </a>
  <a href="https://www.rust-lang.org/">
    <img alt="Rust bootstrap" src="https://img.shields.io/badge/Rust_bootstrap-ef9f76?style=for-the-badge&logo=rust&logoColor=232634&labelColor=414559">
  </a>
  <a href="https://catppuccin.com/">
    <img alt="Catppuccin" src="https://img.shields.io/badge/Catppuccin-Frappe-ca9ee6?style=for-the-badge&logoColor=232634&labelColor=414559">
  </a>
</p>

<p align="center">
  <a href="https://getfedora.org/">
    <img alt="Fedora" src="https://img.shields.io/badge/Fedora-4E9ED3?style=flat-square&logo=fedora&logoColor=white">
  </a>
  <a href="https://fedoraproject.org/atomic-desktops/kinoite/">
    <img alt="Fedora Kinoite" src="https://img.shields.io/badge/Fedora%20Kinoite-4E9ED3?style=flat-square&logo=fedora&logoColor=white">
  </a>
  <a href="https://www.alpinelinux.org/">
    <img alt="Alpine Linux" src="https://img.shields.io/badge/Alpine%20Linux-0D597F?style=flat-square&logo=alpinelinux&logoColor=white">
  </a>
  <a href="https://www.apple.com/os/macos/">
    <img alt="macOS" src="https://img.shields.io/badge/macOS-000000?style=flat-square&logo=apple&logoColor=F0F0F0">
  </a>
  <a href="https://www.microsoft.com/windows/">
    <img alt="Windows" src="https://img.shields.io/badge/Windows-0078D4?style=flat-square&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA4OCA4OCI+PHBhdGggZmlsbD0id2hpdGUiIGQ9Ik0wIDEyLjQgMzYgNy41djM0LjdIMFYxMi40Wm00MC01LjVMODggMHY0Mi4ySDQwVjYuOVpNMCA0Ni4yaDM2djM0LjdMMCA3NlY0Ni4yWm00MCAwaDQ4Vjg4bC00OC02LjZWNDYuMloiLz48L3N2Zz4=&logoColor=white">
  </a>
</p>

> [!IMPORTANT]
> These are personal dotfiles, not a generic installer. Borrow freely, but
> expect to replace hostnames, users, secrets, hardware config, paid font
> settings, and anything that smells like my machine.

## Repo Map

| Path                            | What lives there                                                                                                    |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| [`flake.nix`](flake.nix)        | Nix flake inputs, supported systems, NixOS/nix-darwin exports, and package wiring.                                  |
| [`hosts/linux`](hosts/linux)    | NixOS host configuration, hardware, networking, users, services, sound, and programs.                               |
| [`hosts/darwin`](hosts/darwin)  | nix-darwin host configuration, Tailscale, SOPS, Ghidra MCP, and macOS user setup.                                   |
| [`modules`](modules)            | Shared, Linux, and Darwin modules for packages, fonts, Nix settings, Nixcord, Kanata, launchd, and services.        |
| [`dotfiles`](dotfiles)          | chezmoi templates for shells, editors, terminals, agents, Git, SSH, Yazi, Zellij, Codex, and app configs.           |
| [`bootstrap`](bootstrap)        | The tool manifest used by the Rust `bootstrap` bootstrapper.                                                        |
| [`crates`](crates)              | Rust workspace crates for bootstrap, shared helpers, and chezmoi support scripts.                                   |
| [`pkgs`](pkgs)                  | Custom Nix packages, local Rust tools, patched packages, and private font builder glue.                             |
| [`compose.yaml`](compose.yaml)  | Alpine and Fedora smoke tests for making sure bootstrap still works.                                                |

## System Flow

The basic rule is: Nix owns the machine, bootstrap owns the tools I do not want
to wait on nixpkgs for

Nix is still where the host shape lives: services, patched packages, system
settings, and all the parts that are nicer when they are declarative. Bootstrap
handles the fast-moving userland stuff like Node, bun, uv, ruff, ty,
and yt-dlp. Those tools usually have good upstream binaries, and I would rather
use those than kick off a rebuild because I wanted a newer CLI

```mermaid
flowchart LR
  nix["Nix\nflake, hosts, modules, pkgs\nsystem shape"]
  gate["NixOS first-run gate\nnix-ld + runtime links"]
  boot["Bootstrap\nRust CLI + tools manifest\nchezmoi, uv, node, bun, rustup"]
  home["Dotfiles\nchezmoi apply\nshells, editors, terminals, agents"]
  smoke["Smoke tests\nAlpine + Fedora\nbootstrap doctor"]

  nix --> gate --> boot --> home
  nix -. "macOS / FHS Linux can start here" .-> boot
  smoke -. "checks" .-> boot
  smoke -. "checks" .-> home
```

## Bootstrap

Run this when the machine needs the fast-moving tools:

```bash
bootstrap bootstrap
```

On a brand-new machine, download the latest `bootstrap` binary from the rolling
bootstrap release once, then run it from wherever it landed:

```bash
./bootstrap-linux-x86_64 bootstrap
```

If Rust is already available and this repo is cloned, build and run the
one-time bootstrapper directly from the workspace:

```bash
cargo run --locked --bin bootstrap -- bootstrap
```

From outside the repo, point it at the checkout:

```bash
cargo run --locked --bin bootstrap -- --repo-dir /path/to/nix-dotfiles bootstrap
```

The rolling release is rebuilt whenever [`bootstrap`](bootstrap), [`crates`](crates),
`Cargo.toml`, or `Cargo.lock` changes. It publishes binaries for Linux, macOS,
and Windows under the `bootstrap-rolling` release tag.

<details>
<summary>How the bootstrap is staged</summary>

The first run is staged like this:

1. `bootstrap bootstrap` creates `~/.local/bin` and `~/.local/opt`, installs the
   running `bootstrap` binary into the bootstrap prefix, adds the user-local bin
   directory to the shell environment, and writes the minimal chezmoi config
2. the Rust installer reads [`bootstrap/tools.toml`](bootstrap/tools.toml) and
   installs `chezmoi`, `git`, `uv`, Rust via `rustup`, archive tools like
   `node`, `bun`, and VS Code, `uv tool` packages like `ruff`, `ty`, and
   `yt-dlp`, plus the repo-local Rust tools
3. after that, the machine gets the boring-but-important bits: `chezmoi apply`
   and, where needed, a NixOS or nix-darwin rebuild

NixOS is the one platform where the order flips on first setup. Rebuild NixOS
first so this config can enable the runtime compatibility that upstream Linux
binaries expect without every tool becoming a Nix packaging side quest. After
that first switch, run the bootstrapper through a Nix 3 `nix run` target from
the same flake; the bootstrap binary is provided by the NixOS package set, not
by a pre-existing user `PATH`. On macOS and normal FHS Linux distros, bootstrap
can go first

`chezmoi` comes from its official release archive. Chezmoi hooks call the Rust
`chezmoi-support` helper installed by bootstrap, so the dotfile runtime no
longer depends on a local compiler.

After bootstrap, `bootstrap update` runs the installer in update mode.
`bootstrap doctor` tells you what it can see and where the tools are coming
from. `bootstrap bootstrap` installs `bootstrap` into `~/.local/bin`, so those
commands are the normal entry points once the first run has completed.

On macOS and Linux, Git is still built from source, but `make` is invoked
directly inside an isolated fake-home environment and is never installed as a
bootstrap-managed user tool. On Windows, Git comes from the MinGit archive.

On Linux, Node comes from the official Node.js glibc builds rather than the
unofficial musl builds.

</details>

## System Builds

The first-run order matters:

- **NixOS:** rebuild first, then bootstrap, then `chezmoi`
- **macOS and normal FHS Linux:** bootstrap first, then `chezmoi`, then the Nix
  system if you are using one

### NixOS

```bash
# Replace my secrets or change hosts/linux/users.nix so it does not need them.

# Delete my hardware-configuration.nix and generate one for your machine.
if [ ! -f "hosts/linux/hardware-configuration.nix" ]; then
  nixos-generate-config
  mv "hardware-configuration.nix" "hosts/linux/hardware-configuration.nix"
  rm "configuration.nix"
fi

# Optional: disable private paid fonts if you do not have access to the font repo
# by setting `flame.fonts.paid.enable = false;` in your host config.

nixos-rebuild switch --use-remote-sudo --flake $(readlink -f "/etc/nixos")

# Now nix-ld and runtime compatibility links exist, so upstream binaries can run.
# Use Nix 3 to run the bootstrap package from this NixOS configuration.
nix run "$(readlink -f /etc/nixos)#nixosConfigurations.lenovo-legion.pkgs.bootstrap" -- bootstrap

# Apply the dotfiles.
chezmoi apply --refresh-externals=always --force

# After initial build, you can use the `rebuild` and `cza` aliases.
```

### macOS

```bash
bootstrap bootstrap
chezmoi apply --refresh-externals=always --force

# I use /etc/nixos as the shared flake path on both NixOS and Darwin.
sudo ln -s ~/Developer/nix-dotfiles/ "/etc/nixos"

nix run nix-darwin -- switch --flake $(readlink -f "/etc/nixos/")

sudo darwin-rebuild switch --flake $(readlink -f "/etc/nixos/")

# After initial build, you can use the `rebuild` alias.
```

## Smoke Tests

A Dockerfile that boots an Alpine or Fedora base, runs bootstrap, checks that
`git`, `node`, `npm`, and `npx` came from bootstrap instead of the distro
package manager, applies a focused slice of the dotfiles, and runs `bootstrap doctor`

```bash
# Build and test Alpine.
docker compose build alpine

# Build and test Fedora 44.
docker compose build fedora-44

# Build and test both services.
docker compose build

# Rebuild from scratch when cache is hiding something.
docker compose build --no-cache alpine
docker compose build --no-cache fedora-44
```

After a build, poke at either image:

```bash
docker compose run --rm alpine bootstrap doctor
docker compose run --rm fedora-44 bootstrap doctor

docker compose run --rm alpine node --version
docker compose run --rm fedora-44 node --version
```

`compose.yaml` uses `fedora:44`. That is just the Fedora container base, not the
whole graphical Workstation thing. Compose only picks the base image; the
Dockerfile still does the actual test setup

## Catppuccin Bits

The README uses Catppuccin colors because the rest of the repo already does

| Area               | Config                                                                                                                                                                           |
| ------------------ | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Shell prompt       | [`dotfiles/dot_config/starship.toml`](dotfiles/dot_config/starship.toml)                                                                                                         |
| Editor             | [`dotfiles/dot_config/helix/config.toml`](dotfiles/dot_config/helix/config.toml), [`dotfiles/dot_config/zed/settings.json`](dotfiles/dot_config/zed/settings.json)               |
| Terminal and panes | [`dotfiles/dot_config/ghostty/config.tmpl`](dotfiles/dot_config/ghostty/config.tmpl), [`dotfiles/dot_config/zellij/config.kdl.tmpl`](dotfiles/dot_config/zellij/config.kdl.tmpl) |
| File manager       | [`dotfiles/dot_config/yazi/theme.toml`](dotfiles/dot_config/yazi/theme.toml)                                                                                                     |
| Agent themes       | [`dotfiles/dot_pi/agent/themes`](dotfiles/dot_pi/agent/themes)                                                                                                                   |
| Discord            | [`modules/common/nixcord`](modules/common/nixcord)                                                                                                                               |

## License

This repository is licensed under the terms in [`LICENSE.txt`](LICENSE.txt)
