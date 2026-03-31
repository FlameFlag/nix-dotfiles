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

starship init nu > "$HOME/.cache/starship/init.nu"
zoxide init nushell > "$HOME/.cache/zoxide/init.nu"
atuin init nu --disable-up-arrow > "$HOME/.local/share/atuin/init.nu"

# Workaround for https://github.com/atuinsh/atuin/issues/3308
# atuin v18.13.x generates `e>|` (stderr pipe) instead of `|` in pre_execution hook,
# causing ATUIN_HISTORY_ID to always be empty. Remove once atuin ships the fix.
sed -i'' 's/\$cmd e>| complete/\$cmd | complete/' "$HOME/.local/share/atuin/init.nu"
