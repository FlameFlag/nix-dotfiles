# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_LIB_RELEASE_RPMS_SOURCED:-0} == 1 ]]; then
	return 0
fi
NIX_DOTFILES_SPECTRUM_LIB_RELEASE_RPMS_SOURCED=1

install_latest_release_rpm() {
	local repo=${1:?repo is required}
	local pattern=${2:?asset pattern is required}
	local rpm_url

	rpm_url=$(latest_github_asset_url "$repo" "$pattern")
	dnf_install_no_weak_deps "$rpm_url"
}
