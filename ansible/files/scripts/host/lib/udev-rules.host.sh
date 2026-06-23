# shellcheck shell=bash

rules_file=${1:?rules file is required}
rules=${2:?rules text is required}

require_command install
umask 022
ensure_dir "${rules_file%/*}"
printf "%s\n" "$rules" >"$rules_file"
udevadm control --reload-rules >/dev/null 2>&1 || true
udevadm trigger --subsystem-match=hidraw >/dev/null 2>&1 || true
