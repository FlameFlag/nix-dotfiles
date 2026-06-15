<h1 align="center">nix-dotfiles</h1>

<p align="center">
  <b>Personal Nix and chezmoi configuration</b>
</p>

<p align="center">
  <a href="https://nixos.org"><img alt="NixOS" src="https://img.shields.io/badge/NixOS-303446?style=for-the-badge&logo=nixos&logoColor=c6d0f5&labelColor=232634"></a>
  <a href="https://github.com/nix-darwin/nix-darwin"><img alt="nix-darwin" src="https://img.shields.io/badge/nix--darwin-8caaee?style=for-the-badge&logo=apple&logoColor=232634&labelColor=c6d0f5"></a>
  <a href="https://www.chezmoi.io/"><img alt="chezmoi" src="https://img.shields.io/badge/chezmoi-a6d189?style=for-the-badge&logo=homeassistant&logoColor=232634&labelColor=414559"></a>
  <a href="https://github.com/FlameFlag/scaffold"><img alt="Scaffold" src="https://img.shields.io/badge/Scaffold-Scheme-ef9f76?style=for-the-badge&logo=rust&logoColor=232634&labelColor=414559"></a>
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

## Scaffold

The root [`scaffold.scm`](scaffold.scm) is a Scaffold catalog.

On non-NixOS Unix-like hosts where `scaffold` is not installed yet, bootstrap a
repo-local Scaffold binary from its rolling release and run the catalog with
it. Run this from the repo root:

```bash
set -euo pipefail

case "$(uname -s):$(uname -m)" in
  Darwin:arm64) scaffold_asset="scaffold-rolling-aarch64-apple-darwin" ;;
  Darwin:x86_64) scaffold_asset="scaffold-rolling-x86_64-apple-darwin" ;;
  Linux:x86_64) scaffold_asset="scaffold-rolling-x86_64-unknown-linux-gnu" ;;
  *) echo "unsupported platform: $(uname -s):$(uname -m)" >&2; exit 1 ;;
esac

mkdir -p .cache/scaffold
curl -fsSL --retry 3 \
  "https://github.com/FlameFlag/scaffold/releases/download/rolling/${scaffold_asset}.tar.gz" |
  tar -xzf - -C .cache/scaffold

"./.cache/scaffold/${scaffold_asset}/scaffold" install
```

On macOS, the catalog includes a `scaffold` tool entry so that first bootstrap
also installs or refreshes the user-local `scaffold` binary without using Nix
profiles. NixOS does not need this bootstrap step because the system rebuild
installs Scaffold from the flake.

## System Builds

- **NixOS:** rebuild first, run Scaffold from the rebuilt system, then apply
  `chezmoi`
- **Non-NixOS:** bootstrap Scaffold from the rolling release, run Scaffold,
  then apply `chezmoi`

### NixOS

```bash
# Replace my secrets or change hosts/linux/users.nix so it does not need them

# Delete my hardware-configuration.nix and generate one for your machine
if [ ! -f "hosts/linux/hardware-configuration.nix" ]; then
  nixos-generate-config
  mv "hardware-configuration.nix" "hosts/linux/hardware-configuration.nix"
  rm "configuration.nix"
fi

nixos-rebuild switch --use-remote-sudo --flake $(readlink -f "/etc/nixos")

# Install/update user-space tools managed outside the NixOS closure
scaffold install

# Apply the dotfiles
chezmoi apply --refresh-externals=always --force

# After initial build, you can use the `rebuild` and `cza` aliases
```

### macOS

```bash
# I use /etc/nixos as the shared flake path on both NixOS and Darwin.
sudo ln -s ~/Developer/nix-dotfiles/ "/etc/nixos"

nix run nix-darwin -- switch --flake $(readlink -f "/etc/nixos/")

sudo darwin-rebuild switch --flake $(readlink -f "/etc/nixos/")

# If this is the first setup, run the non-NixOS bootstrap command in the Scaffold
# section first. Later runs can use the installed binary directly.
scaffold install

chezmoi apply --refresh-externals=always --force

# After initial build, you can use the `rebuild` alias.
```

### Immutable Linux With Containerized Nix

```bash
# Bluefin and other ostree hosts usually cannot create /nix on the host.
nix run .#immutable-activate -- --backend container --reset-containers
chezmoi apply --refresh-externals=always --force
```

The container backend keeps Nix inside managed Distrobox containers and exports
commands through `distrobox-export` into
`~/.local/share/nix-dotfiles/immutable/bin`. Keep that directory on `PATH`
before `~/.local/bin`; the dotfiles shell templates do this automatically.

If `nix` already exists on the host, the direct profile activator is still
available:

```bash
nix run .#immutable-activate
chezmoi apply --refresh-externals=always --force
```

After first setup:

```bash
# Refresh flake inputs, update native host/user package managers when present,
# rebuild the immutable profile, refresh wrappers, and run Scaffold.
update

# Rebuild the immutable profile, refresh wrappers, and run Scaffold without
# changing flake inputs or the host OS.
rebuild

# Check the flake and build the immutable profile.
check
```

## Formatting

Run the repo formatter with:

```bash
nix fmt
```

It formats Nix through `treefmt`, Go through `gofumpt`, and Scheme config
through `scaffold fmt`.

## Smoke Tests

A Dockerfile boots Alpine or Fedora, builds the repo-local helpers, and applies
a focused slice of the dotfiles

```bash
# Build and test Alpine.
docker compose build alpine

# Build and test Fedora 44.
docker compose build fedora-44

# Build and test all services.
docker compose build

# Rebuild from scratch when cache is hiding something.
docker compose build --no-cache alpine
docker compose build --no-cache fedora-44
```

After a build, inspect any image:

```bash
docker compose run --rm alpine
docker compose run --rm fedora-44
```

Open an interactive shell inside either smoke image:

```bash
docker compose --profile shell run --rm alpine-shell
docker compose --profile shell run --rm fedora-44-shell
```

## License

This repository is licensed under the terms in [`LICENSE.txt`](LICENSE.txt)
