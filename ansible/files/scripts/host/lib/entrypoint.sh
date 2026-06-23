# shellcheck shell=bash

if [[ ${NIX_DOTFILES_HOST_LIB_ENTRYPOINT_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_ENTRYPOINT_SOURCED=1

case ${BASH_SOURCE[0]} in
*/*) host_entrypoint_lib_dir=${BASH_SOURCE[0]%/*} ;;
*) host_entrypoint_lib_dir=. ;;
esac
host_entrypoint_lib_dir=$(cd -P -- "$host_entrypoint_lib_dir" && pwd -P)

export NIX_DOTFILES_HOST_SCRIPT_ROOT
NIX_DOTFILES_HOST_SCRIPT_ROOT=$(cd -P -- "$host_entrypoint_lib_dir/.." && pwd -P)
export NIX_DOTFILES_REPO_ROOT
NIX_DOTFILES_REPO_ROOT=$(cd -P -- "$NIX_DOTFILES_HOST_SCRIPT_ROOT/../../../.." && pwd -P)

# shellcheck disable=SC1091
source -p "$host_entrypoint_lib_dir" core.sh
