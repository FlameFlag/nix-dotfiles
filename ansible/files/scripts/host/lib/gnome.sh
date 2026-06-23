# shellcheck shell=bash
# shellcheck disable=SC2016

if [[ ${NIX_DOTFILES_HOST_LIB_GNOME_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_GNOME_SOURCED=1

host_lib_dir=${BASH_SOURCE[0]%/*}
# shellcheck disable=SC1091
source -p "$host_lib_dir" host.sh

host_gnome_shell_available() {
  run_host_user_bash 'command -v gnome-shell >/dev/null 2>&1 && command -v gnome-extensions >/dev/null 2>&1'
}

host_gnome_shell_major_version() {
  run_host_user_bash_file "$host_lib_dir/gnome-version.host.sh"
}

host_enable_gnome_extensions() {
  if (($# == 0)); then
    return
  fi

  run_host_user_bash_file "$host_lib_dir/gnome-enable.host.sh" "$@"
}
