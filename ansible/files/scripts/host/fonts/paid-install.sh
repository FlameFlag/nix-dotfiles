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
source_host_lib host
source_host_lib paths

require_arg_count 0 1 "$@"
home=${1:-$HOME}
require_value 'home directory' "$home"
require_safe_path "$home"

run_host_bash_file "$script_dir/paid.host.sh" "$home"
