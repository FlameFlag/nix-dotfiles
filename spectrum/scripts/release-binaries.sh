# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_SCRIPT_RELEASE_BINARIES_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_SPECTRUM_SCRIPT_RELEASE_BINARIES_SOURCED=1

install_spectrum_yazi() {
  local target=${1:?target is required}
  local archive ya_bin yazi_bin work

  require_commands find install unzip
  make_temp_dir work
  archive="${work}/yazi.zip"
  download_file \
    "$(latest_github_asset_url sxyazi/yazi "yazi-${target}\\.zip")" \
    "$archive"
  unzip -q "$archive" -d "$work"
  yazi_bin=$(find "$work" -type f -name yazi -perm /111 -print -quit)
  ya_bin=$(find "$work" -type f -name ya -perm /111 -print -quit)
  [[ -n "$yazi_bin" ]] || die "binary yazi not found in yazi-${target}.zip"
  [[ -n "$ya_bin" ]] || die "binary ya not found in yazi-${target}.zip"
  install -D -m 0755 "$yazi_bin" /usr/bin/yazi
  install -D -m 0755 "$ya_bin" /usr/bin/ya
  rm -rf "$work"
}

install_spectrum_release_binaries() {
  local gnu_target musl_target pfetch_asset

  if ! musl_target=$(rust_linux_musl_target); then
    printf 'Skipping GitHub release binaries for unsupported architecture: %s\n' "$(machine_arch)" >&2
    return 0
  fi

  gnu_target=$(rust_linux_gnu_target)
  pfetch_asset=$(pfetch_asset_name)

  install_latest_tar_binary \
    zellij-org/zellij \
    "zellij-${musl_target}\\.tar\\.gz" \
    zellij \
    /usr/bin/zellij
  install_latest_tar_binary \
    atuinsh/atuin \
    "atuin-${musl_target}\\.tar\\.gz" \
    atuin \
    /usr/bin/atuin
  install_zip_member \
    "$(latest_github_asset_url Canop/broot "broot_[0-9].*\\.zip")" \
    "${musl_target}/broot" \
    /usr/bin/broot
  install_latest_tar_binary \
    ClementTsang/bottom \
    "bottom_${musl_target}\\.tar\\.gz" \
    btm \
    /usr/bin/btm
  install_latest_tar_binary \
    Gobidev/pfetch-rs \
    "${pfetch_asset//./\\.}" \
    pfetch \
    /usr/bin/pfetch
  install_latest_tar_binary \
    chmln/sd \
    "sd-v[0-9].*-${musl_target}\\.tar\\.gz" \
    sd \
    /usr/bin/sd
  install_latest_tar_binary \
    alexpasmantier/television \
    "tv-[0-9].*-${gnu_target}\\.tar\\.gz" \
    tv \
    /usr/bin/tv
  install_latest_tar_binary \
    ducaale/xh \
    "xh-v[0-9].*-${musl_target}\\.tar\\.gz" \
    xh \
    /usr/bin/xh
  install_spectrum_yazi "$musl_target"
}
