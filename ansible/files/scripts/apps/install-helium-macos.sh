#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

case ${BASH_SOURCE[0]} in
*/*) script_dir=${BASH_SOURCE[0]%/*} ;;
*) script_dir=. ;;
esac
script_dir=$(cd -P -- "$script_dir" && pwd -P)

# shellcheck disable=SC1091
source -p "$script_dir/../host/lib" entrypoint.sh
source_host_lib fs

require_arg_count 4 5 "$@"
root=$1
bin_dir=$2
installer_bin=$3
secrets_file=$4
flags=${5:-}
require_value 'cache root' "$root"
require_value 'bin dir' "$bin_dir"
require_value 'installer bin dir' "$installer_bin"
require_value 'Helium secrets file' "$secrets_file"
require_safe_path "$root"
require_safe_path "$bin_dir"
require_safe_path "$installer_bin"
require_file "$secrets_file"
require_commands go sops

ensure_dir "$root"
ensure_dir "$bin_dir"
ensure_dir "$installer_bin"

GOBIN="$installer_bin" go install ./cmd/helium-browser
"$installer_bin/helium-browser" install \
  --secrets "$secrets_file" \
  -- \
  macos \
  "$root" \
  "$bin_dir" \
  "$flags"
