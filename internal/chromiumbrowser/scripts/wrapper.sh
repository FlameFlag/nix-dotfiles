#!/usr/bin/env bash
# shellcheck shell=bash

set -Eeuo pipefail
unset DESKTOP_STARTUP_ID STARTUP_NOTIFICATION_ID XDG_ACTIVATION_TOKEN
unset FONTCONFIG_SYSROOT
export FONTCONFIG_FILE="${FONTCONFIG_FILE:-/etc/fonts/fonts.conf}"
export FONTCONFIG_PATH="${FONTCONFIG_PATH:-/etc/fonts}"
case ":${XDG_DATA_DIRS:-}:" in
*:/usr/share:* | *:/usr/share/:*) ;;
*) export XDG_DATA_DIRS="${XDG_DATA_DIRS:+$XDG_DATA_DIRS:}/usr/local/share:/usr/share" ;;
esac

runtime_flags=()

append_flags_file() {
  local file=${1:?flags file is required}
  [[ -r "$file" ]] || return 0

  local line safe_line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) ]] && continue
    if [[ "$line" == *\$\(* || "$line" == *\`* ]]; then
      printf 'helium-browser: ignoring unsafe flag line in %s: %s\n' "$file" "$line" >&2
      continue
    fi

    set -f
    safe_line=${line//$/\\$}
    safe_line=${safe_line//~/\\~}
    eval "set -- $safe_line"
    set +f
    runtime_flags+=("$@")
  done <"$file"
}

XDG_CONFIG_HOME=${XDG_CONFIG_HOME:-"$HOME/.config"}
append_flags_file "$XDG_CONFIG_HOME/helium-flags.conf"

exec __COMMAND__ "${runtime_flags[@]}" "$@"
