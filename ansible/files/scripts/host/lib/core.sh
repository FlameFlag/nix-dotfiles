# shellcheck shell=bash

if [[ ${NIX_DOTFILES_HOST_LIB_CORE_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_CORE_SOURCED=1
NIX_DOTFILES_HOST_LIB_DIR=${BASH_SOURCE[0]%/*}

die() {
  printf '%s\n' "$*" >&2
  exit 1
}

require_bash_version() {
  local major=${1:?major Bash version is required}
  local minor=${2:?minor Bash version is required}

  if ((BASH_VERSINFO[0] < major || (BASH_VERSINFO[0] == major && BASH_VERSINFO[1] < minor))); then
    die "Bash $major.$minor or newer is required; found $BASH_VERSION"
  fi
}

require_bash_version 5 3
# Keep host scripts on the Bash behavior this library is written for. These are
# Bash 5.2/5.3 options that make array expansion, library loading, globbing,
# and temporary file descriptors less surprising in automation.
shopt -s inherit_errexit array_expand_once bash_source_fullpath globskipdots varredir_close

source_host_lib() {
  local module=${1:?host lib module is required}

  case "$module" in
  "" | "." | ".." | */*)
    die "host lib module must be a single path component"
    ;;
  esac

  # shellcheck source=/dev/null
  source -p "$NIX_DOTFILES_HOST_LIB_DIR" "$module.sh"
}

require_non_empty() {
  local value=${1-}
  local message=${2:?error message is required}

  if [[ -z $value ]]; then
    die "$message"
  fi
}

require_value() {
  local name=${1:?value name is required}
  local value=${2-}

  if [[ -z $value ]]; then
    die "$name is required"
  fi
}

require_arg_count() {
  local min=${1:?minimum argument count is required}
  local max=${2:?maximum argument count is required}
  shift 2
  local count=$#

  if ((count < min || count > max)); then
    if [[ $min == "$max" ]]; then
      die "expected $min arguments, got $count"
    fi

    die "expected between $min and $max arguments, got $count"
  fi
}

require_command() {
  local command_name=${1:?command name is required}

  if ! command -v "$command_name" >/dev/null 2>&1; then
    die "required command is not available: $command_name"
  fi
}

require_commands() {
  local command_name

  for command_name; do
    require_command "$command_name"
  done
}

require_file() {
  local path=${1:?file path is required}

  if [[ ! -f $path ]]; then
    die "required file does not exist: $path"
  fi
}

require_executable() {
  local path=${1:?executable path is required}

  if [[ ! -x $path ]]; then
    die "required executable does not exist or is not executable: $path"
  fi
}
