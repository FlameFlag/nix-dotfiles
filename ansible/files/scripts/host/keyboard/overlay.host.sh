# shellcheck shell=bash

if ! command -v gsettings >/dev/null 2>&1; then
  exit 0
fi
if [[ $(gsettings get org.gnome.mutter overlay-key 2>/dev/null || printf "''") == "''" ]]; then
  gsettings set org.gnome.mutter overlay-key Super_L
fi
