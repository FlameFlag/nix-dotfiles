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
source_host_lib host

require_arg_count 0 0 "$@"

run_host_bash 'if command -v fc-cache >/dev/null 2>&1; then fc-cache -f /usr/local/share/fonts/nix-dotfiles-paid /usr/share/fonts; fi'

if command -v fc-cache >/dev/null 2>&1; then
  fc-cache -f /usr/local/share/fonts/nix-dotfiles-paid /usr/share/fonts || true
fi

fontconfig_cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/fontconfig"
if [[ -d $fontconfig_cache_dir ]]; then
  declare -a fontconfig_cache_files=()
  declare -a fontconfig_cache_entries=()
  declare fontconfig_cache_entry
  direct_child_paths_into fontconfig_cache_entries "$fontconfig_cache_dir"
  for fontconfig_cache_entry in "${fontconfig_cache_entries[@]}"; do
    if [[ $fontconfig_cache_entry == *cache-11 ]]; then
      fontconfig_cache_files+=("$fontconfig_cache_entry")
    fi
  done
  if ((${#fontconfig_cache_files[@]} > 0)); then
    require_command rm
    rm -f -- "${fontconfig_cache_files[@]}"
  fi
fi
