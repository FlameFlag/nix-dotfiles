#!/usr/bin/env bash
# shellcheck shell=bash
set -eu

profile_bin="$HOME/.nix-profile/bin"
if [ ! -d "$profile_bin" ]; then
  exit 0
fi

rm -rf "$NIX_DOTFILES_LAUNCHER_DIR"
mkdir -p "$NIX_DOTFILES_LAUNCHER_DIR"

real_profile_bin=$(readlink -f "$profile_bin")
find "$real_profile_bin" -maxdepth 1 \( -type f -o -type l \) -perm /111 -print | sort | while IFS= read -r source; do
  name=${source##*/}
  launcher="$NIX_DOTFILES_LAUNCHER_DIR/$name"
  {
    printf "%s\n" "#!/bin/sh"
    printf "export PATH=\"%s\"\n" "$NIX_DOTFILES_CONTAINER_PATH"
    printf "exec \"%s\" \"\$@\"\n" "$profile_bin/$name"
  } >"$launcher"
  chmod 0755 "$launcher"
  distrobox-export --bin "$launcher" --export-path "$NIX_DOTFILES_EXPORT_DIR" >/dev/null
done
