# shellcheck shell=bash

if [[ ${NIX_DOTFILES_HOST_LIB_JSON_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_JSON_SOURCED=1

host_lib_dir=${BASH_SOURCE[0]%/*}
# shellcheck disable=SC1091
source -p "$host_lib_dir" core.sh

jq_read() {
  local filter=${1:?jq filter is required}
  local path=${2:?JSON path is required}

  require_command jq
  require_file "$path"
  jq -er "$filter" "$path"
}

jq_read_arg() {
  local filter=${1:?jq filter is required}
  local arg_name=${2:?jq argument name is required}
  local arg_value=${3-}
  local path=${4:?JSON path is required}

  require_command jq
  require_file "$path"
  jq -er --arg "$arg_name" "$arg_value" "$filter" "$path"
}

jq_read_text() {
  local filter=${1:?jq filter is required}
  local input=${2-}

  require_command jq
  jq -er "$filter" <<<"$input"
}
