#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

source_nix=${1:?source nixcord module is required}
dest=${2:?destination settings.json is required}
tmp=$(mktemp)

cleanup() {
	rm -f -- "$tmp"
}
trap cleanup EXIT

require_command() {
	local command_name=${1:?command name is required}

	if ! command -v "$command_name" >/dev/null 2>&1; then
		printf 'error: required command not found: %s\n' "$command_name" >&2
		exit 127
	fi
}

require_command jq
require_command nix

source_nix=$(realpath "$source_nix")
nix_source_string=$(jq -Rn --arg path "$source_nix" '$path')

nix eval --impure --json --expr "
let
  module = import ${nix_source_string} {};
in
  module.programs.nixcord.config
" |
	jq '
    def plugin_name:
      ({
        clearUrls: "ClearURLs",
        favoriteEmojiFirst: "FavoriteEmojiFirst",
        fixYoutubeEmbeds: "FixYoutubeEmbeds",
        hideMedia: "HideMedia",
        mutualGroupDms: "MutualGroupDMs",
        onePingPerDm: "OnePingPerDM",
        questify: "Questify",
        streamerModeOnStream: "StreamerModeOn",
        voiceChatDoubleClick: "VoiceChatDoubleClick",
        youtubeAdblock: "YoutubeAdblock"
      }[.] // ((.[0:1] | ascii_upcase) + .[1:]));

    def setting_name:
      if . == "enable" then "enabled" else . end;

    {
      useQuickCss: (.useQuickCss // false),
      plugins: (
        (.plugins // {})
        | to_entries
        | map({
            key: (.key | plugin_name),
            value: (.value | with_entries(.key |= setting_name))
          })
        | from_entries
      )
    }
  ' >"$tmp"

if [[ -f $dest ]] && cmp -s "$tmp" "$dest"; then
	printf '%s\n' unchanged
	exit 0
fi

install -D -m 0644 "$tmp" "$dest"
printf '%s\n' changed
