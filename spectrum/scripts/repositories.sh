# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_SCRIPT_REPOSITORIES_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_SPECTRUM_SCRIPT_REPOSITORIES_SOURCED=1

install_spectrum_rpm_repositories() {
  local node_arch version_id

  install_rpm_repo_file \
    "${CTX_DIR}/repos/vscode.repo" \
    /etc/yum.repos.d/vscode.repo

  install_downloaded_rpm_repo \
    https://downloads.1password.com/linux/keys/1password.asc \
    /etc/pki/rpm-gpg/RPM-GPG-KEY-1password
  install_rpm_repo_file \
    "${CTX_DIR}/repos/1password.repo" \
    /etc/yum.repos.d/1password.repo

  install_downloaded_rpm_repo \
    https://pkgs.tailscale.com/stable/fedora/tailscale.repo \
    /etc/yum.repos.d/tailscale.repo

  if node_arch=$(fedora_arch); then
    render_rpm_repo_template \
      "${CTX_DIR}/repos/nodesource-nodejs.repo.in" \
      /etc/yum.repos.d/nodesource-nodejs.repo \
      "s/@NODE_ARCH@/${node_arch}/g"
  else
    printf 'Skipping NodeSource repository for unsupported architecture: %s\n' "$(machine_arch)" >&2
  fi

  version_id=$(fedora_version_id)
  install_downloaded_rpm_repo \
    "https://copr.fedorainfracloud.org/coprs/iolaum/aitoolkit/repo/fedora-${version_id}/iolaum-aitoolkit-fedora-${version_id}.repo" \
    /etc/yum.repos.d/iolaum-aitoolkit.repo
  install_downloaded_rpm_repo \
    "https://copr.fedorainfracloud.org/coprs/scottames/ghostty/repo/fedora-${version_id}/scottames-ghostty-fedora-${version_id}.repo" \
    /etc/yum.repos.d/scottames-ghostty.repo
}
