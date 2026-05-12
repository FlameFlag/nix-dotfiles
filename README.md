# My dotfiles

[![Fedora](https://img.shields.io/badge/Fedora-4E9ED3?style=for-the-badge&logo=fedora&logoColor=white)](https://getfedora.org/)

[![Fedora Kinoite](https://img.shields.io/badge/Fedora%20Kinoite-4E9ED3?style=for-the-badge&logo=fedora&logoColor=white)](https://fedoraproject.org/atomic-desktops/kinoite/)

[![NixOS](https://img.shields.io/badge/NixOS-5277C3?style=for-the-badge&logo=nixos&logoColor=white)](https://nixos.org)

[![macOS](https://img.shields.io/badge/macOS-000000?style=for-the-badge&logo=apple&logoColor=F0F0F0)](https://www.apple.com/os/macos/)

This repo has my dotfiles for Linux and macOS (Darwin)

## Modules

[system.nix](hosts/darwin/system.nix) - Here I keep all my macOS system
settings; they're pretty opinionated compared to the macOS defaults, but I think
they're very sensible

## Catppuccin

[catppuccin-userstyles.nix](pkgs/catppuccin-userstyles.nix) - Conveniently
enough, Catppuccin has their theme for a bunch of sites. I love consistency, so
I think it's a must-have

If you want to build my dotfiles, here's how to do it:

### NixOS

```bash
chezmoi apply --refresh-externals=always --force

# Override secrets with your own or modify hosts/linux/users.nix to not use secrets

# Delete my hardware-configuration.nix and create your own one
if [ ! -f "hosts/linux/hardware-configuration.nix" ]; then
  nixos-generate-config
  mv "hardware-configuration.nix" "hosts/linux/hardware-configuration.nix"
  rm "configuration.nix"
fi

# Optional: disable private paid fonts if you do not have access to the font repo
# by setting `flame.fonts.paid.enable = false;` in your host config.

nixos-rebuild switch --use-remote-sudo --flake $(readlink -f "/etc/nixos")

# After initial build, you can use the `rebuild` alias
```

### macOS (Darwin)

```bash
chezmoi apply --refresh-externals=always --force

# This repo uses /etc/nixos as a shared convenience symlink on both NixOS and Darwin.
sudo ln -s ~/Developer/nix-dotfiles/ "/etc/nixos"

nix run nix-darwin -- switch --flake $(readlink -f "/etc/nixos/")

sudo darwin-rebuild switch --flake $(readlink -f "/etc/nixos/")

# After initial build, you can use the `rebuild` alias
```
