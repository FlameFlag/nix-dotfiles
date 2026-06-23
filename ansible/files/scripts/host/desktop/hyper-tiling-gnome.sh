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
source_host_lib host

require_arg_count 0 0 "$@"

bash "$script_dir/gnome-extension.sh" \
  hyper-window-tiling-gnome \
  hyper-window-tiling@flame.local \
  hyper-window-tiling

host_data_home=$(run_host_user_bash 'printf "%s\n" "${XDG_DATA_HOME:-$HOME/.local/share}"')
schema_dir="$host_data_home/gnome-shell/extensions/hyper-window-tiling@flame.local/schemas"
if [[ ! -d $schema_dir ]]; then
  exit 0
fi

run_host_user_bash_file "$script_dir/gnome-keys.host.sh" "$schema_dir"
