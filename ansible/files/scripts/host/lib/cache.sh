# shellcheck shell=bash

if [[ ${NIX_DOTFILES_HOST_LIB_CACHE_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_CACHE_SOURCED=1

host_lib_dir=${BASH_SOURCE[0]%/*}
# shellcheck disable=SC1091
source -p "$host_lib_dir" fs.sh

host_download_dir() {
  local name=${1:?tool name is required}
  require_path_component 'tool name' "$name"

  printf '%s\n' "$HOME/.local/share/nix-dotfiles/immutable/host-downloads/$name"
}

fresh_host_staging_dir() {
  local name=${1:?tool name is required}
  local staging
  require_path_component 'tool name' "$name"
  staging="$HOME/.local/share/nix-dotfiles/immutable/host-bin-staging/$name"

  fresh_dir "$staging"
  printf '%s\n' "$staging"
}

nix_dotfiles_cache_dir() {
  local name=${1:?cache name is required}
  require_path_component 'cache name' "$name"

  printf '%s\n' "${XDG_CACHE_HOME:-$HOME/.cache}/nix-dotfiles/$name"
}
