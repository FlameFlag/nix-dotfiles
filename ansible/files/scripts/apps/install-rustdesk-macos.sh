#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

case ${BASH_SOURCE[0]} in
*/*) script_dir=${BASH_SOURCE[0]%/*} ;;
*) script_dir=. ;;
esac
script_dir=$(cd -P -- "$script_dir" && pwd -P)

# shellcheck disable=SC1091
source -p "$script_dir/../host/lib" entrypoint.sh
source_host_lib fs
source_host_lib github

require_arg_count 3 3 "$@"
root=$1
bin_dir=$2
rustdesk_arch=$3
require_value 'cache root' "$root"
require_value 'bin dir' "$bin_dir"
require_value 'RustDesk architecture' "$rustdesk_arch"
require_safe_path "$root"
require_safe_path "$bin_dir"
require_commands curl ditto hdiutil install jq ln mkdir rm

repository=rustdesk/rustdesk
release_json="$root/rustdesk-release.json"
mount_dir="$root/mount"
app_dst=/Applications/RustDesk.app
settings_dir="$HOME/Library/Preferences/com.carriez.RustDesk"
settings_file="$settings_dir/RustDesk2.toml"
settings_source="$script_dir/rustdesk/RustDesk2.toml"
launch_agents_dir="$HOME/Library/LaunchAgents"
launch_agent="$launch_agents_dir/com.carriez.RustDesk.plist"
launch_agent_source="$script_dir/rustdesk/com.carriez.RustDesk.plist"

ensure_dir "$root"
ensure_dir "$bin_dir"
require_file "$settings_source"
require_file "$launch_agent_source"
github_latest_release_json "$repository" "$release_json"

asset_pattern="rustdesk-.*-${rustdesk_arch}[.]dmg$"
declare dmg_url
github_release_asset_url_from_file_into dmg_url "$repository" "$asset_pattern" "$release_json"

dmg="$root/${dmg_url##*/}"
curl_download "$dmg_url" "$dmg"

fresh_dir "$mount_dir"
hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_dir"
trap 'hdiutil detach "$mount_dir" >/dev/null 2>&1 || true' EXIT

remove_path "$app_dst"
ditto "$mount_dir/RustDesk.app" "$app_dst"

if [[ -x "$app_dst/Contents/MacOS/RustDesk" ]]; then
  ln -sfn "$app_dst/Contents/MacOS/RustDesk" "$bin_dir/rustdesk"
fi

ensure_dir "$settings_dir"
install -m 0644 "$settings_source" "$settings_file"

ensure_dir "$launch_agents_dir"
install -m 0644 "$launch_agent_source" "$launch_agent"

if command -v launchctl >/dev/null 2>&1; then
  launchctl unload "$launch_agent" >/dev/null 2>&1 || true
  launchctl load "$launch_agent" >/dev/null 2>&1 || true
fi

cat >&2 <<EOF
rustdesk-macos: installed /Applications/RustDesk.app
rustdesk-macos: configured direct IP access in $settings_file
rustdesk-macos: enabled login startup via $launch_agent
rustdesk-macos: grant RustDesk Accessibility and Screen Recording in System Settings > Privacy & Security.
rustdesk-macos: grant Input Monitoring too if keyboard or mouse input does not work.
EOF
