# shellcheck shell=bash

if [[ ${NIX_DOTFILES_HOST_LIB_PLATFORM_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_PLATFORM_SOURCED=1

host_lib_dir=${BASH_SOURCE[0]%/*}
# shellcheck disable=SC1091
source -p "$host_lib_dir" core.sh

host_arch() {
  uname -m
}

normalized_host_arch() {
  case "$(host_arch)" in
  x86_64 | amd64) printf '%s\n' x86_64 ;;
  aarch64 | arm64) printf '%s\n' arm64 ;;
  *) unsupported_host_arch "${1:?tool name is required}" ;;
  esac
}

unsupported_host_arch() {
  die "unsupported architecture for ${1:?tool name is required}: $(host_arch)"
}

host_linux_arch() {
  case "$(normalized_host_arch "${1:?tool name is required}")" in
  x86_64) printf '%s\n' x86_64 ;;
  arm64) printf '%s\n' aarch64 ;;
  *) unsupported_host_arch "${1:?tool name is required}" ;;
  esac
}

host_linux_musl_target() {
  case "$(normalized_host_arch "${1:?tool name is required}")" in
  x86_64) printf '%s\n' x86_64-unknown-linux-musl ;;
  arm64) printf '%s\n' aarch64-unknown-linux-musl ;;
  *) unsupported_host_arch "${1:?tool name is required}" ;;
  esac
}

require_host_arch() {
  local expected=${1:?expected architecture is required}
  local name=${2:?tool name is required}
  local actual

  actual=$(normalized_host_arch "$name")
  if [[ $actual != "$expected" ]]; then
    unsupported_host_arch "$name"
  fi
}
