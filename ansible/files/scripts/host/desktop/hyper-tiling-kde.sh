#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016
set -euo pipefail

case ${BASH_SOURCE[0]} in
*/*) script_dir=${BASH_SOURCE[0]%/*} ;;
*) script_dir=. ;;
esac
script_dir=$(cd -P -- "$script_dir" && pwd -P)

# shellcheck disable=SC1091
source -p "$script_dir/../lib" entrypoint.sh
source_host_lib fs
source_host_lib host

require_arg_count 0 0 "$@"

if ! run_host_user_bash_file "$script_dir/kde-check.host.sh"; then
  printf '%s\n' "hyper-window-tiling: KDE Plasma is not available; skipping"
  exit 0
fi

require_command nix
require_command cp
require_command readlink

repo_dir=$NIX_DOTFILES_REPO_ROOT
require_file "$repo_dir/flake.nix"

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/nix-dotfiles/hyper-window-tiling
out_link="$state_dir/hyper-window-tiling-kde"
install_source="$state_dir/kwin-script/hyper-window-tiling"

ensure_dir "$state_dir"
nix \
  --extra-experimental-features "nix-command flakes" \
  build \
  --out-link "$out_link" \
  "$repo_dir#hyper-window-tiling-kde"

if ! package_path=$(readlink -f "$out_link" 2>/dev/null); then
  package_path=$(readlink "$out_link")
fi

source_dir="$package_path/share/kwin-wayland/scripts/hyper-window-tiling"
require_file "$source_dir/metadata.json"

ensure_dir "${install_source%/*}"
fresh_dir "$install_source"
cp -R -- "$source_dir/." "$install_source/"

installed_with_kpackage=false
kpackage=$(run_host_user_bash 'command -v kpackagetool6 || command -v kpackagetool5 || true')
if [[ -n $kpackage ]]; then
  if run_host_user "$kpackage" --type KWin/Script --upgrade "$install_source" >/dev/null 2>&1 \
    || run_host_user "$kpackage" --type KWin/Script --install "$install_source" >/dev/null 2>&1; then
    installed_with_kpackage=true
  fi
fi

if [[ $installed_with_kpackage != true ]]; then
  host_data_home=$(run_host_user_bash 'printf "%s\n" "${XDG_DATA_HOME:-$HOME/.local/share}"')
  for destination in \
    "$host_data_home/kwin/scripts/hyper-window-tiling" \
    "$host_data_home/kwin-wayland/scripts/hyper-window-tiling"; do
    ensure_dir "${destination%/*}"
    fresh_dir "$destination"
    cp -R -- "$install_source/." "$destination/"
  done
fi

kwriteconfig=$(run_host_user_bash 'command -v kwriteconfig6 || command -v kwriteconfig5 || true')
if [[ -n $kwriteconfig ]]; then
  run_host_user \
    "$kwriteconfig" \
    --file kwinrc \
    --group Plugins \
    --key hyper-window-tilingEnabled \
    true >/dev/null 2>&1 || true
fi

qdbus=$(run_host_user_bash 'command -v qdbus6 || command -v qdbus || true')
if [[ -n $qdbus ]]; then
  run_host_user "$qdbus" org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true
fi

printf '%s\n' "hyper-window-tiling: installed KDE script"
