# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_SCRIPT_DISCORD_SOURCED:-0} == 1 ]]; then
	return 0
fi
NIX_DOTFILES_SPECTRUM_SCRIPT_DISCORD_SOURCED=1

install_spectrum_discord() {
	ensure_dnf_cmd
	"${DNF_CMD[@]}" -y install \
		--nogpgcheck \
		--setopt=install_weak_deps=False \
		'https://discord.com/api/download?platform=linux&format=rpm'
}
