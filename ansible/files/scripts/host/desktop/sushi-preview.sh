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

require_arg_count 0 0 "$@"

repo_dir=$NIX_DOTFILES_REPO_ROOT
installer="$repo_dir/packages/sushi/install-sushi-preview-flatpak.sh"
require_file "$installer"

run_host_user env \
  NIX_DOTFILES_SUSHI_PATCH_DIR="$repo_dir/packages/sushi/patches" \
  bash "$installer"
