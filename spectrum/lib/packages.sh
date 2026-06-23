# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_LIB_PACKAGES_SOURCED:-0} == 1 ]]; then
	return 0
fi
NIX_DOTFILES_SPECTRUM_LIB_PACKAGES_SOURCED=1

trim_spectrum_package_line() {
	local value=$1

	value=${value//$'\r'/}
	value=${value##+([[:space:]])}
	value=${value%%+([[:space:]])}
	printf '%s\n' "$value"
}

read_spectrum_package_manifest() {
	local manifest=${1:?package manifest is required}
	local scope=${2:?package scope is required}
	local __result_var=${3:?result variable is required}
	local -n __packages="$__result_var"
	local extglob_was_set=0
	local current_scope=
	local in_packages=0
	local raw_line line package

	require_readable_file "$manifest"
	__packages=()

	if shopt -q extglob; then
		extglob_was_set=1
	fi
	shopt -s extglob

	while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
		line=${raw_line%%#*}
		line=$(trim_spectrum_package_line "$line")

		[[ -n "$line" ]] || continue

		if [[ $line =~ ^\[([[:alnum:]_-]+)\.([[:alnum:]_-]+)\]$ ]]; then
			current_scope=${BASH_REMATCH[1]}
			in_packages=0
			continue
		fi

		if [[ $line == "packages = [" ]]; then
			in_packages=1
			continue
		fi

		if [[ $line == "]" ]]; then
			in_packages=0
			continue
		fi

		if ((in_packages)) && [[ $current_scope == "$scope" ]]; then
			if [[ $line =~ ^\"([^\"]+)\"[,]?$ ]]; then
				package=${BASH_REMATCH[1]}
				__packages+=("$package")
				continue
			fi

			die "unsupported package entry in ${manifest}: ${raw_line}"
		fi
	done <"$manifest"

	if ((extglob_was_set == 0)); then
		shopt -u extglob
	fi
}
