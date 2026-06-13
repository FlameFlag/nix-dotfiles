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

The root [`scaffold.scm`](scaffold.scm) is a Scaffold catalog. It includes a
macOS `scaffold` tool entry so Scaffold can install or refresh itself without
using Nix profiles:

```bash
scaffold install scaffold
```

## System Builds

- **NixOS:** rebuild first, run Scaffold, then apply `chezmoi`
- **macOS:** install Nix, switch nix-darwin, then run Scaffold or `chezmoi`

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

chezmoi apply --refresh-externals=always --force

# After initial build, you can use the `rebuild` alias.
```

### Immutable Linux With Containerized Nix

```bash
# Bluefin and other ostree hosts usually cannot create /nix on the host.
packages/immutable-activate.sh --backend container --reset-containers
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

It formats Nix through `treefmt`, Rust through `cargo fmt`, and Scheme config
through `scaffold fmt`.

## Smoke Tests

A Dockerfile boots Alpine or Fedora, builds the repo-local helpers, and applies
a focused slice of the dotfiles. Bluefin and other immutable hosts are covered
on real machines instead of Docker because their public images are large and
unreliable on Apple Silicon Docker.

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
docker compose run --rm alpine scaffold --help
docker compose run --rm fedora-44 scaffold --help
```

## License

This repository is licensed under the terms in [`LICENSE.txt`](LICENSE.txt)
