# shellcheck shell=bash

if [[ ${NIX_DOTFILES_SPECTRUM_LIB_COMMON_SOURCED:-0} == 1 ]]; then
	return 0
fi
NIX_DOTFILES_SPECTRUM_LIB_COMMON_SOURCED=1

case ${BASH_SOURCE[0]} in
	*/*) spectrum_common_lib_dir=${BASH_SOURCE[0]%/*} ;;
	*) spectrum_common_lib_dir=. ;;
esac
SPECTRUM_LIB_DIR=${SPECTRUM_LIB_DIR:-$(cd -P -- "$spectrum_common_lib_dir" && pwd -P)}
TEMP_DIRS=()
DNF_CMD=()

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

require_bash_version() {
	local major=${1:?major Bash version is required}
	local minor=${2:?minor Bash version is required}

	if ((BASH_VERSINFO[0] < major || (BASH_VERSINFO[0] == major && BASH_VERSINFO[1] < minor))); then
		die "Bash ${major}.${minor} or newer is required; found ${BASH_VERSION}"
	fi
}

source_spectrum_lib() {
	local module=${1:?Spectrum lib module is required}

	case "$module" in
		"" | "." | ".." | */*)
			die "Spectrum lib module must be a single path component"
			;;
	esac

	# shellcheck source=/dev/null
	source -p "$SPECTRUM_LIB_DIR" "${module}.sh"
}

require_arg_count() {
	local min=${1:?minimum argument count is required}
	local max=${2:?maximum argument count is required}
	shift 2
	local count=$#

	if ((count < min || count > max)); then
		if [[ $min == "$max" ]]; then
			die "expected ${min} arguments, got ${count}"
		fi

		die "expected between ${min} and ${max} arguments, got ${count}"
	fi
}

cleanup_temp_dirs() {
	local dir

	for dir in "${TEMP_DIRS[@]}"; do
		if [[ -n "$dir" && -d "$dir" ]]; then
			rm -rf -- "$dir"
		fi
	done
}

make_temp_dir() {
	local __result_var=${1:?result variable is required}
	local dir

	dir=$(mktemp -d) || die "failed to create temporary directory"
	TEMP_DIRS+=("$dir")
	printf -v "$__result_var" '%s' "$dir"
}

require_command() {
	local command_name

	for command_name in "$@"; do
		command -v "$command_name" >/dev/null 2>&1 \
			|| die "required command not found: ${command_name}"
	done
}

require_commands() {
	require_command "$@"
}

require_readable_file() {
	local file=${1:?file is required}

	[[ -r "$file" ]] || die "required file is not readable: ${file}"
}

download_file() {
	local url=${1:?url is required}
	local dest=${2:?destination is required}
	local -a curl_args=(-fsSL --retry 3 --retry-delay 2 --retry-connrefused)

	require_command curl
	curl "${curl_args[@]}" -o "$dest" "$url"
}

machine_arch() {
	uname -m
}

fedora_arch() {
	case "$(machine_arch)" in
		x86_64) printf '%s\n' x86_64 ;;
		aarch64 | arm64) printf '%s\n' aarch64 ;;
		*) return 1 ;;
	esac
}

rust_linux_musl_target() {
	case "$(machine_arch)" in
		x86_64) printf '%s\n' x86_64-unknown-linux-musl ;;
		aarch64 | arm64) printf '%s\n' aarch64-unknown-linux-musl ;;
		*) return 1 ;;
	esac
}

rust_linux_gnu_target() {
	case "$(machine_arch)" in
		x86_64) printf '%s\n' x86_64-unknown-linux-gnu ;;
		aarch64 | arm64) printf '%s\n' aarch64-unknown-linux-gnu ;;
		*) return 1 ;;
	esac
}

pfetch_asset_name() {
	case "$(machine_arch)" in
		x86_64) printf '%s\n' pfetch-linux-musl-x86_64.tar.gz ;;
		aarch64 | arm64) printf '%s\n' pfetch-linux-musl-aarch64.tar.gz ;;
		*) return 1 ;;
	esac
}

resolve_dnf_cmd() {
	if command -v dnf5 >/dev/null 2>&1; then
		DNF_CMD=(dnf5)
	elif command -v dnf >/dev/null 2>&1; then
		DNF_CMD=(dnf)
	else
		die "required command not found: dnf5 or dnf"
	fi
}

ensure_dnf_cmd() {
	if ((${#DNF_CMD[@]} == 0)); then
		resolve_dnf_cmd
	fi
}

dnf_install_no_weak_deps() {
	ensure_dnf_cmd
	"${DNF_CMD[@]}" -y install \
		--setopt=install_weak_deps=False \
		"$@"
}

dnf_install_optional_no_weak_deps() {
	ensure_dnf_cmd
	"${DNF_CMD[@]}" -y install \
		--skip-unavailable \
		--setopt=install_weak_deps=False \
		"$@"
}

clean_dnf_metadata() {
	ensure_dnf_cmd
	"${DNF_CMD[@]}" clean all
	rm -rf \
		/run/dnf \
		/var/cache/dnf/* \
		/var/cache/ldconfig/aux-cache \
		/var/cache/libdnf5/* \
		/var/lib/dnf/repos \
		/var/lib/dnf/system-repo.lock \
		/var/lib/sepolgen \
		/var/log/dnf* \
		/var/log/hawkey.log
}
