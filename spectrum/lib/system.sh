# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_LIB_SYSTEM_SOURCED:-0} == 1 ]]; then
	return 0
fi
NIX_DOTFILES_SPECTRUM_LIB_SYSTEM_SOURCED=1

disable_authselect_feature() {
	local feature=${1:?authselect feature is required}

	if command -v authselect >/dev/null 2>&1 && authselect is-feature-enabled "$feature"; then
		authselect disable-feature "$feature"
	fi
}

enable_system_services() {
	local service

	for service in "$@"; do
		systemctl enable "$service"
	done
}
