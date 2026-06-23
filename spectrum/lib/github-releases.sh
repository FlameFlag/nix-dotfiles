# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_LIB_GITHUB_RELEASES_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_SPECTRUM_LIB_GITHUB_RELEASES_SOURCED=1

latest_github_asset_url() {
  local repo=${1:?repo is required}
  local pattern=${2:?asset pattern is required}
  local helper="${CTX_DIR}/scripts/latest-github-asset-url.sh"

  require_readable_file "$helper"
  bash "$helper" "$repo" "$pattern"
}
