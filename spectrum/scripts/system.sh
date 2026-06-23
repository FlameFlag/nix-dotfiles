# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_SCRIPT_SYSTEM_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_SPECTRUM_SCRIPT_SYSTEM_SOURCED=1

configure_spectrum_system() {
  disable_authselect_feature with-fingerprint
  enable_system_services podman.socket tailscaled.service pcscd.socket
}
