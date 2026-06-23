#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

usage() {
	printf 'usage: %s OWNER/REPO ASSET_REGEX\n' "${0##*/}" >&2
}

die() {
	printf 'error: %s\n' "$*" >&2
	exit 1
}

require_command() {
	local command_name

	for command_name in "$@"; do
		command -v "$command_name" >/dev/null 2>&1 ||
			die "required command not found: ${command_name}"
	done
}

if (($# != 2)); then
	usage
	exit 2
fi

repo=$1
asset_pattern=$2
release_url="https://api.github.com/repos/${repo}/releases/latest"

require_command curl jq

release_json=$(
	curl \
		-fsSL \
		--retry 3 \
		--retry-delay 2 \
		--retry-connrefused \
		--header 'Accept: application/vnd.github+json' \
		--user-agent 'nix-dotfiles-spectrum-build' \
		"$release_url"
)

asset_url=$(
	jq -er \
		--arg pattern "^(${asset_pattern})$" \
		'[.assets[]? | select((.name // "") | test($pattern)) | .browser_download_url][0] // empty' \
		<<<"$release_json"
) || die "no asset matching ${asset_pattern@Q} in ${repo} latest release; assets: $(jq -r '[.assets[]?.name // ""] | join(", ")' <<<"$release_json")"

printf '%s\n' "$asset_url"
