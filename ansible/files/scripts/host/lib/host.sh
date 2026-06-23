# shellcheck shell=bash
# shellcheck disable=SC2016

if [[ ${NIX_DOTFILES_HOST_LIB_HOST_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_HOST_SOURCED=1

host_lib_dir=${BASH_SOURCE[0]%/*}
# shellcheck disable=SC1091
source -p "$host_lib_dir" fs.sh

host_bash_prelude() {
  printf '%s\n' 'set -euo pipefail'
  declare -f \
    die \
    require_bash_version \
    require_command \
    require_commands \
    require_file \
    require_safe_path \
    require_path_component \
    remove_path \
    ensure_dir
  printf '%s\n' \
    'require_bash_version 5 3' \
    'shopt -s inherit_errexit array_expand_once bash_source_fullpath globskipdots varredir_close'
}

run_host_bash() {
  local script=${1:?host Bash script is required}
  shift
  local prelude

  prelude=$(host_bash_prelude)
  run_host bash -c "$prelude"$'\n'"$script" bash "$@"
}

run_host_bash_file() {
  local script_path=${1:?host Bash script path is required}
  shift

  require_file "$script_path"
  run_host_bash "$(<"$script_path")" "$@"
}

run_host_user_bash() {
  local script=${1:?host user Bash script is required}
  shift
  local prelude

  prelude=$(host_bash_prelude)
  run_host_user bash -c "$prelude"$'\n'"$script" bash "$@"
}

run_host_user_bash_file() {
  local script_path=${1:?host user Bash script path is required}
  shift

  require_file "$script_path"
  run_host_user_bash "$(<"$script_path")" "$@"
}

run_host() {
  if (($# == 0)); then
    die 'run_host requires a command'
  fi

  if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
    require_command distrobox-host-exec
    distrobox-host-exec sudo -n "$HOME/.local/bin/system-runner" -- "$@"
  else
    require_command sudo
    require_executable "$HOME/.local/bin/system-runner"
    sudo -n "$HOME/.local/bin/system-runner" -- "$@"
  fi
}

run_host_user() {
  if (($# == 0)); then
    die 'run_host_user requires a command'
  fi

  if [[ -f /.dockerenv || -f /run/.containerenv ]]; then
    require_command distrobox-host-exec
    distrobox-host-exec "$@"
  else
    "$@"
  fi
}

host_has_command() {
  local command_name=${1:?command name is required}

  run_host_user_bash 'command -v "$1" >/dev/null 2>&1' "$command_name"
}

require_host_user_command() {
  local command_name=${1:?command name is required}
  local label=${2:-$command_name}

  if ! host_has_command "$command_name"; then
    die "$label: $command_name is not available on the host"
  fi
}

ensure_host_bin_dir() {
  run_host install -d -m 0755 /usr/local/bin
}

install_host_bin() {
  local src=${1:?source binary is required}
  local bin=${2:?binary name is required}

  require_path_component 'binary name' "$bin"
  require_executable "$src"
  ensure_host_bin_dir
  run_host install -m 0755 "$src" "/usr/local/bin/$bin"
}
