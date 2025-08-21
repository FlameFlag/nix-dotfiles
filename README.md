# My Nix dotfiles

[![built with nix](https://img.shields.io/static/v1?logo=nixos&logoColor=white&label=&message=Built%20with%20Nix&color=41439a)](https://builtwithnix.org)

This repo contains my personal dotfiles for NixOS and macOS (Darwin)

It has some interesting stuff in [lib](/lib/) and [modules](/modules/)

## Modules

[system.nix](/hosts/darwin/system.nix) - Here I keep all my macOS system
settings; they're pretty opinionated compared to the macOS defaults, but I think
they're very sensible

[nixcord.nix](/modules/hm/guis/nixcord.nix) - My
[Nixcord](https://github.com/KaylorBen/nixcord) config; it has the Catppuccin
theme and a bunch of QoL (Quality of Life) plugins, making using Discord much
nicer

## Catppuccin

Unfortunately, some programs (and projects) don't have a linter, so I made my
own little solutions for this

[catppuccin-userstyles.nix](/pkgs/catppuccin-userstyles.nix) -
Conveniently enough, Catppuccin has their theme for a bunch of sites. I love
consistency, so I think it's a must-have, tbh

[warp-terminal-catppuccin.nix](/pkgs/warp-terminal-catppuccin.nix) -
Warp Terminal

## Scripts

[yt-dlp-script.sh](scripts/yt-dlp-script.sh) - A bash script, I have to
download video in my own "niche" format

[update.sh](/pkgs/update.sh) - A neat bash script
I have to update any custom modules I have *(e.g
[catppuccin-userstyles.nix](/modules/hm/custom/catppuccin-userstyles.n
ix))*

If you want to build my dotfiles, here's how to do it:

### NixOS

```bash
# Override secrets with your own or modify hosts/nixos/users.nix to not use secrets

# Delete my hardware-configuration.nix and create your own one
if [ ! -f "hosts/nixos/hardware-configuration.nix" ]; then
  nixos-generate-config
  mv "hardware-configuration.nix" "hosts/nixos/nyx"
  rm "configuration.nix"
fi

nixos-rebuild switch --use-remote-sudo --flake $(readlink -f "/etc/nixos")

# After initial build, you can use the `rebuild` alias
```

### macOS (Darwin)

```bash
nix --experimental-features 'nix-command flakes' nix-darwin -- switch --flake $(readlink -f "/etc/nixos/")

sudo darwin-rebuild switch --flake $(readlink -f "/etc/nixos/")

# After initial build, you can use the `rebuild` alias
```
