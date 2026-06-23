# shellcheck shell=bash

if [[ ${NIX_DOTFILES_HOST_LIB_GITHUB_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_GITHUB_SOURCED=1

host_lib_dir=${BASH_SOURCE[0]%/*}
# shellcheck disable=SC1091
source -p "$host_lib_dir" http.sh
# shellcheck disable=SC1091
source -p "$host_lib_dir" json.sh

github_latest_release_json() {
  local repository=${1:?GitHub repository is required}
  local dest=${2:?release JSON destination is required}

  curl_download "https://api.github.com/repos/$repository/releases/latest" "$dest"
}

github_latest_release_tag_from_file() {
  local repository=${1:?GitHub repository is required}
  local path=${2:?release JSON path is required}
  local tag

  if ! tag=$(jq_read '.tag_name // empty' "$path"); then
    die "$repository: failed to discover latest release"
  fi

  printf '%s\n' "$tag"
}

github_latest_release_tag() {
  local repository=${1:?GitHub repository is required}
  local release_json
  local tag

  if ! release_json=$(curl_stdout "https://api.github.com/repos/$repository/releases/latest") \
    || ! tag=$(jq_read_text '.tag_name // empty' "$release_json"); then
    die "$repository: failed to discover latest release"
  fi

  printf '%s\n' "$tag"
}

github_latest_release_tag_into() {
  local -n tag_ref=${1:?tag variable is required}
  local repository=${2:?GitHub repository is required}
  local release_json

  # shellcheck disable=SC2034
  if ! release_json=$(curl_stdout "https://api.github.com/repos/$repository/releases/latest") \
    || ! tag_ref=$(jq_read_text '.tag_name // empty' "$release_json"); then
    die "$repository: failed to discover latest release"
  fi
}

github_release_asset_url_from_file_into() {
  local -n url_ref=${1:?asset URL variable is required}
  local repository=${2:?GitHub repository is required}
  local pattern=${3:?asset regex is required}
  local path=${4:?release JSON path is required}

  # shellcheck disable=SC2016,SC2034
  if ! url_ref=$(jq_read_arg \
    '[.assets[].browser_download_url | select(test($pattern))][0] // empty' \
    pattern \
    "$pattern" \
    "$path"); then
    die "$repository: failed to discover asset matching $pattern"
  fi
}

github_release_asset_digest_from_file_into() {
  local -n digest_ref=${1:?asset digest variable is required}
  local repository=${2:?GitHub repository is required}
  local pattern=${3:?asset regex is required}
  local path=${4:?release JSON path is required}

  # shellcheck disable=SC2016,SC2034
  if ! digest_ref=$(jq_read_arg \
    '[.assets[] | select(.browser_download_url | test($pattern)) | .digest][0] // empty' \
    pattern \
    "$pattern" \
    "$path"); then
    die "$repository: failed to discover asset digest matching $pattern"
  fi
}
