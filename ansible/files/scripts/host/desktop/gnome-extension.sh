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
source_host_lib gnome

require_arg_count 3 3 "$@"

attr=${1:?Nix attr is required}
uuid=${2:?GNOME extension UUID is required}
label=${3:?extension label is required}

if ! host_gnome_shell_available; then
  printf '%s\n' "$label: GNOME Shell is not available; skipping"
  exit 0
fi

require_command nix
require_command cp
require_command readlink

nix_container_name() {
  local nix_path

  nix_path=$(command -v nix) || return 1
  if ! grep -aq '# nix-dotfiles: immutable-container-wrapper' "$nix_path"; then
    return 1
  fi

  sed -n 's/^# name: //p' "$nix_path" | head -n 1
}

repo_dir=$NIX_DOTFILES_REPO_ROOT
require_file "$repo_dir/flake.nix"

state_dir=${XDG_STATE_HOME:-$HOME/.local/state}/nix-dotfiles/gnome-extensions
out_link="$state_dir/$attr"
host_data_home=$(run_host_user_bash 'printf "%s\n" "${XDG_DATA_HOME:-$HOME/.local/share}"')
host_bin_dir=$(run_host_user_bash 'printf "%s\n" "$HOME/.local/bin"')
destination="$host_data_home/gnome-shell/extensions/$uuid"

ensure_dir "$state_dir"
if [[ -n ${CONTAINER_ID:-} ]]; then
  nix \
    --extra-experimental-features "nix-command flakes" \
    build \
    --out-link "$out_link" \
    "$repo_dir#$attr"

  if ! package_path=$(readlink -f "$out_link" 2>/dev/null); then
    package_path=$(readlink "$out_link")
  fi
  source_dir="$package_path/share/gnome-shell/extensions/$uuid"
  require_file "$source_dir/metadata.json"

  ensure_dir "${destination%/*}"
  if [[ -e $destination ]]; then
    chmod -R u+rwX "$destination"
  fi
  remove_path "$destination"
  ensure_dir "$destination"
  cp -R -- "$source_dir/." "$destination/"
  if [[ -d $package_path/bin ]]; then
    ensure_dir "$host_bin_dir"
    while IFS= read -r -d "" source_path; do
      target_path="$host_bin_dir/${source_path##*/}"
      if [[ -e $target_path ]]; then
        chmod -R u+rwX "$target_path"
        remove_path "$target_path"
      fi
    done < <(find "$package_path/bin" -mindepth 1 -maxdepth 1 -print0)
    cp -R -- "$package_path/bin/." "$host_bin_dir/"
  fi
elif container_name=$(nix_container_name); then
  require_command distrobox
  distrobox enter --name "$container_name" -- nix \
    --extra-experimental-features "nix-command flakes" \
    build \
    --out-link "$out_link" \
    "$repo_dir#$attr"

  distrobox enter --name "$container_name" -- bash "$script_dir/gnome-copy.sh" "$out_link" "$uuid" "$destination" "$host_bin_dir"
else
  run_host_user nix \
    --extra-experimental-features "nix-command flakes" \
    build \
    --out-link "$out_link" \
    "$repo_dir#$attr"

  run_host_user bash "$script_dir/gnome-copy.sh" "$out_link" "$uuid" "$destination" "$host_bin_dir"
fi

run_host_user gnome-extensions enable "$uuid" >/dev/null 2>&1 || true
host_enable_gnome_extensions "$uuid"

printf '%s\n' "$label: installed GNOME extension $uuid"
