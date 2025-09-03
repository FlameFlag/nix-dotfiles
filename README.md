# My Nix dotfiles

[![built with nix](https://img.shields.io/static/v1?logo=nixos&logoColor=white&label=&message=Built%20with%20Nix&color=41439a)](https://builtwithnix.org)

This repo contains my personal dotfiles for NixOS and macOS (Darwin)

It has some interesting stuff in [lib](lib/) and [modules](modules/)

## myLib

`myLib`, as the name suggests, is a `lib` that has functions I made for my own
purposes and use. It mainly has functions for modules where, without custom
functions, creating configurations would be too verbose

A few highlights from `myLib` include:

[kanata.nix](lib/kanata.nix): This is the most impressive part of `myLib`. It
contains _a bunch_ of functions for generating LISP Schema code for Kanata.
Somewhat ironically, this requires more code than raw LISP, but it's easier to
reason about if you're used to the Nix language and not LISP

[zellij.nix](lib/zellij.nix): Although less impressive, it actually uses less
code (unlike [kanata.nix](lib/kanata.nix)). Its main purpose is not only to make
Zellij configuration easier but also to make it much less verbose

[ghostty.nix](lib/ghostty.nix): It's basically for the same reasons as Zellij,
but here the idea is more about keeping the code in Nix. The generated code is
about the same as the Nix one (perhaps even less), but again, I want to keep
things in the Nix language

## Modules

[system.nix](hosts/darwin/system.nix) - Here I keep all my macOS system
settings; they're pretty opinionated compared to the macOS defaults, but I think
they're very sensible

[nixcord.nix](modules/hm/guis/nixcord.nix) - My
[Nixcord](https://github.com/KaylorBen/nixcord) config; it has the Catppuccin
theme and a bunch of QoL (Quality of Life) plugins, making using Discord much
nicer

## Catppuccin

Unfortunately, some programs (and projects) don't have a linter, so I made my
own little solutions for this

[catppuccin-userstyles.nix](pkgs/catppuccin-userstyles.nix) - Conveniently
enough, Catppuccin has their theme for a bunch of sites. I love consistency, so
I think it's a must-have, tbh

[warp-terminal-catppuccin.nix](pkgs/warp-terminal-catppuccin.nix) - Warp
Terminal

## Scripts

[yt-dlp-script.sh](scripts/yt-dlp-script.sh) - A bash script, I have to download
video in my own "niche" format

[update.sh](pkgs/update.sh) - A neat bash script
I have to update any custom modules I have *(e.g
[catppuccin-userstyles.nix](modules/hm/custom/catppuccin-userstyles.nix))*

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
