# shellcheck shell=bash
# shellcheck disable=SC2016

if [[ ${NIX_DOTFILES_HOST_LIB_UDEV_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_UDEV_SOURCED=1

host_lib_dir=${BASH_SOURCE[0]%/*}
# shellcheck disable=SC1091
source -p "$host_lib_dir" host.sh

install_host_udev_rules() {
  local rules_file=${1:?udev rules file is required}
  local rules=${2:?udev rules text is required}

  run_host_bash_file "$host_lib_dir/udev-rules.host.sh" "$rules_file" "$rules"
}
