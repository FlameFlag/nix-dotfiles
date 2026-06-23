# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_LIB_REPOS_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_SPECTRUM_LIB_REPOS_SOURCED=1

install_rpm_repo_file() {
  local src=${1:?source repo file is required}
  local dest=${2:?destination repo file is required}

  require_commands install
  require_readable_file "$src"
  install -d -m 0755 /etc/pki/rpm-gpg /etc/yum.repos.d
  install -m 0644 "$src" "$dest"
}

install_downloaded_rpm_repo() {
  local url=${1:?url is required}
  local dest=${2:?destination repo file is required}

  require_commands install
  install -d -m 0755 /etc/pki/rpm-gpg /etc/yum.repos.d
  download_file "$url" "$dest"
}

render_rpm_repo_template() {
  local src=${1:?source repo template is required}
  local dest=${2:?destination repo file is required}
  local sed_expr=${3:?sed expression is required}

  require_commands install sed
  require_readable_file "$src"
  install -d -m 0755 /etc/pki/rpm-gpg /etc/yum.repos.d
  sed "$sed_expr" "$src" >"$dest"
}

fedora_version_id() {
  require_readable_file /usr/lib/os-release
  # shellcheck disable=SC1091
  source /usr/lib/os-release
  printf '%s\n' "${VERSION_ID:?VERSION_ID is required in /usr/lib/os-release}"
}
