#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

case ${BASH_SOURCE[0]} in
*/*) script_dir=${BASH_SOURCE[0]%/*} ;;
*) script_dir=. ;;
esac
script_dir=$(cd -P -- "$script_dir" && pwd -P)

# shellcheck disable=SC1091
source -p "$script_dir/../lib" entrypoint.sh
source_host_lib fs
source_host_lib paths

require_arg_count 0 1 "$@"
home=${1:-$HOME}
require_value 'home directory' "$home"
require_safe_path "$home"
require_command install
src="$home/.nix-profile/share/fonts"
staging="$home/.local/share/nix-dotfiles/immutable/host-fonts/paid"
declare -a fonts=()

fresh_dir "$staging"

if [[ -e $src ]]; then
  recursive_files_by_extension_into fonts "$src" ttf otf ttc otc

  for font in "${fonts[@]}"; do
    rel=${font#"$src"/}
    target="$staging/$rel"
    ensure_dir "${target%/*}"
    install -m 0644 "$font" "$target"
  done
fi
