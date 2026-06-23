# shellcheck shell=bash

if [[ ${NIX_DOTFILES_HOST_LIB_HTTP_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_HTTP_SOURCED=1

host_lib_dir=${BASH_SOURCE[0]%/*}
# shellcheck disable=SC1091
source -p "$host_lib_dir" core.sh

curl_download() {
  local url=${1:?download URL is required}
  local dest=${2:?download destination is required}
  local -a curl_args=(-fsSL --retry 3 --retry-delay 1 --retry-connrefused)

  require_command curl
  curl "${curl_args[@]}" -o "$dest" "$url"
}

curl_stdout() {
  local url=${1:?download URL is required}
  local -a curl_args=(-fsSL --retry 3 --retry-delay 1 --retry-connrefused)

  require_command curl
  curl "${curl_args[@]}" "$url"
}
