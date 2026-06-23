# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_LIB_ARCHIVE_INSTALL_SOURCED:-0} == 1 ]]; then
	return 0
fi
NIX_DOTFILES_SPECTRUM_LIB_ARCHIVE_INSTALL_SOURCED=1

install_tar_binary() {
	local url=${1:?url is required}
	local bin=${2:?binary is required}
	local dest=${3:?destination is required}
	local archive src work

	require_commands find install tar
	make_temp_dir work
	archive="${work}/archive.tar.gz"
	download_file "$url" "$archive"
	tar -xzf "$archive" -C "$work"
	src=$(find "$work" -type f -name "$bin" -perm /111 -print -quit)
	[[ -n "$src" ]] || die "binary ${bin} not found in ${url}"
	install -D -m 0755 "$src" "$dest"
	rm -rf "$work"
}

install_zip_member() {
	local url=${1:?url is required}
	local member=${2:?zip member is required}
	local dest=${3:?destination is required}
	local archive extracted work

	require_commands install unzip
	make_temp_dir work
	archive="${work}/archive.zip"
	extracted="${work}/member"
	download_file "$url" "$archive"
	unzip -p "$archive" "$member" >"$extracted"
	install -D -m 0755 "$extracted" "$dest"
	rm -rf "$work"
}
