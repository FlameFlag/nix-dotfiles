# shellcheck shell=bash

if [[ ${NIX_DOTFILES_HOST_LIB_PATHS_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_PATHS_SOURCED=1

host_lib_dir=${BASH_SOURCE[0]%/*}
# shellcheck disable=SC1091
source -p "$host_lib_dir" core.sh

require_safe_path() {
  local path=${1:?path is required}

  case "$path" in
  "" | "/" | "." | "..")
    die "refusing unsafe path: $path"
    ;;
  esac
}

require_path_component() {
  local name=${1:?component name is required}
  local value=${2-}

  case "$value" in
  "" | "." | ".." | */*)
    die "$name must be a single path component"
    ;;
  esac
}
