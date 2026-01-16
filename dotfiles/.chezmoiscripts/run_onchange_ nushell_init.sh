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
atuin init nu > "$HOME/.local/share/atuin/init.nu"
