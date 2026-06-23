# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_LIB_RELEASE_BINARIES_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_SPECTRUM_LIB_RELEASE_BINARIES_SOURCED=1

install_latest_tar_binary() {
  local repo=${1:?repo is required}
  local pattern=${2:?asset pattern is required}
  local bin=${3:?binary is required}
  local dest=${4:?destination is required}

  install_tar_binary "$(latest_github_asset_url "$repo" "$pattern")" "$bin" "$dest"
}
