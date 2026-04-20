#!/usr/bin/env bash
#
# Author: FlameFlag
#

set -euo pipefail

dirs=(
    "$HOME/.cache/starship"
    "$HOME/.cache/zoxide"
    "$HOME/.local/share/atuin"
)

for dir in "${dirs[@]}"; do
    mkdir -p "$dir"
done

gen() {
    local bin=$1 out=$2
    shift 2
    if command -v "$bin" >/dev/null 2>&1; then
        "$bin" "$@" > "$out"
    fi
}

gen starship "$HOME/.cache/starship/init.nu" init nu
gen zoxide   "$HOME/.cache/zoxide/init.nu"   init nushell
gen atuin    "$HOME/.local/share/atuin/init.nu" init nu --disable-up-arrow

# Workaround for https://github.com/atuinsh/atuin/issues/3308
# atuin v18.13.x generates `e>|` (stderr pipe) instead of `|` in pre_execution hook,
# causing ATUIN_HISTORY_ID to always be empty. Remove once atuin ships the fix.
if [[ -f "$HOME/.local/share/atuin/init.nu" ]]; then
    sed -i'' "s/\\\$cmd e>| complete/\\\$cmd | complete/" "$HOME/.local/share/atuin/init.nu"
fi
