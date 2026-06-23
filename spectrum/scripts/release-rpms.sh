# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_SCRIPT_RELEASE_RPMS_SOURCED:-0} == 1 ]]; then
	return 0
fi
NIX_DOTFILES_SPECTRUM_SCRIPT_RELEASE_RPMS_SOURCED=1

install_spectrum_release_rpms() {
	local rpm_arch

	if ! rpm_arch=$(fedora_arch); then
		printf 'Skipping GitHub release RPMs for unsupported architecture: %s\n' "$(machine_arch)" >&2
		return 0
	fi

	install_latest_release_rpm \
		getsops/sops \
		"sops-[0-9].*-1\\.${rpm_arch}\\.rpm"
	install_latest_release_rpm \
		rustdesk/rustdesk \
		"rustdesk-[0-9].*-0\\.${rpm_arch}\\.rpm"
}
