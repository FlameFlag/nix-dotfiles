<h1 align="center">nix-dotfiles</h1>

<p align="center">
  <b>Personal Nix and chezmoi configuration</b>
</p>

<p align="center">
  <a href="https://nixos.org"><img alt="NixOS" src="https://img.shields.io/badge/NixOS-303446?style=for-the-badge&logo=nixos&logoColor=c6d0f5&labelColor=232634"></a>
  <a href="https://github.com/nix-darwin/nix-darwin"><img alt="nix-darwin" src="https://img.shields.io/badge/nix--darwin-8caaee?style=for-the-badge&logo=apple&logoColor=232634&labelColor=c6d0f5"></a>
  <a href="https://www.chezmoi.io/"><img alt="chezmoi" src="https://img.shields.io/badge/chezmoi-a6d189?style=for-the-badge&logo=homeassistant&logoColor=232634&labelColor=414559"></a>
  <a href="https://www.rust-lang.org/"><img alt="Rust bootstrap" src="https://img.shields.io/badge/Rust_bootstrap-ef9f76?style=for-the-badge&logo=rust&logoColor=232634&labelColor=414559"></a>
  <a href="https://catppuccin.com/"><img alt="Catppuccin" src="https://img.shields.io/badge/Catppuccin-Frappe-f4b8e4?style=for-the-badge&logoColor=232634&labelColor=414559"></a>
</p>

<p align="center">
  <a href="https://getfedora.org/"><img alt="Fedora" src="https://img.shields.io/badge/Fedora-8caaee?style=flat-square&logo=fedora&logoColor=232634"></a>
  <a href="https://fedoraproject.org/atomic-desktops/kinoite/"><img alt="Fedora Kinoite" src="https://img.shields.io/badge/Fedora%20Kinoite-99d1db?style=flat-square&logo=fedora&logoColor=232634"></a>
  <a href="https://www.alpinelinux.org/"><img alt="Alpine Linux" src="https://img.shields.io/badge/Alpine%20Linux-81c8be?style=flat-square&logo=alpinelinux&logoColor=232634"></a>
  <a href="https://www.apple.com/os/macos/"><img alt="macOS" src="https://img.shields.io/badge/macOS-f4b8e4?style=flat-square&logo=apple&logoColor=232634"></a>
  <a href="https://www.microsoft.com/windows/"><img alt="Windows" src="https://img.shields.io/badge/Windows-8caaee?style=flat-square&logo=data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA4OCA4OCI+PHBhdGggZmlsbD0iIzIzMjYzNCIgZD0iTTAgMTIuNCAzNiA3LjV2MzQuN0gwVjEyLjRabTQwLTUuNUw4OCAwdjQyLjJINDBWNi45Wk0wIDQ2LjJoMzZ2MzQuN0wwIDc2VjQ2LjJabTQwIDBoNDhWODhsLTQ4LTYuNlY0Ni4yWiIvPjwvc3ZnPg==&logoColor=232634"></a>
</p>

> [!IMPORTANT]
> This is a personal dotfiles repo, not a generic installer. Expect to replace
> hostnames, users, secrets, hardware config, paid font settings, and other
> machine-specific values.

## System Flow

Nix defines the system state. `bootstrap` installs user-space tools that either
are not in nixpkgs or need to update independently.

Host-level configuration stays in Nix: services, patched packages, system
settings, and anything else that is easier to keep declarative.

## Bootstrap

```bash
bootstrap bootstrap
```

On a brand-new machine, download the latest `bootstrap` binary from the
[latest bootstrap release](https://github.com/FlameFlag/nix-dotfiles/releases/latest)
once, then run it from wherever it landed:

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
3. after that, the machine gets the remaining setup steps: `chezmoi apply`
   and, where needed, a NixOS or nix-darwin rebuild

NixOS is the one platform where the order flips on first setup. Rebuild NixOS
first so this config can enable the runtime compatibility that upstream Linux
binaries expect. After that first switch, run the bootstrapper through a Nix
3 `nix run` target from the same flake; the bootstrap binary is provided by
the NixOS package set. On macOS and normal FHS Linux distros, bootstrap can
go first.

`chezmoi` comes from its official release archive. Chezmoi hooks call the Rust
`chezmoi-support` helper installed by bootstrap, so the dotfile runtime no
longer depends on a local compiler.

After bootstrap, `bootstrap update` runs the installer in update mode.
`bootstrap doctor` tells you what it can see and where the tools are coming
from. `bootstrap bootstrap` installs `bootstrap` into `~/.local/bin`, so those
commands are the normal entry points once the first run has completed.

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

After a build, inspect either image:

```bash
docker compose run --rm alpine bootstrap doctor
docker compose run --rm fedora-44 bootstrap doctor

docker compose run --rm alpine node --version
docker compose run --rm fedora-44 node --version
```

## License

This repository is licensed under the terms in [`LICENSE.txt`](LICENSE.txt)
