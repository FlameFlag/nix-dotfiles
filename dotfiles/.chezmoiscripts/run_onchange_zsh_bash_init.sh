#!/usr/bin/env bash
#
# Author: FlameFlag
#

set -euo pipefail

# Create cache directories
dirs=(
    "$HOME/.cache/starship"
    "$HOME/.cache/zoxide"
    "$HOME/.cache/atuin"
    "$HOME/.cache/television"
    "$HOME/.cache/zsh/completions"
    "$HOME/.cache/bash/completions"
)

for dir in "${dirs[@]}"; do
    mkdir -p "$dir"
done

has() { command -v "$1" >/dev/null 2>&1; }

# Generate init files for zsh and bash
for shell in zsh bash; do
    has starship && starship init "$shell" > "$HOME/.cache/starship/init.$shell"
    has zoxide   && zoxide init "$shell" > "$HOME/.cache/zoxide/init.$shell"
    has atuin    && atuin init "$shell" --disable-up-arrow > "$HOME/.cache/atuin/init.$shell"
    has tv       && tv init "$shell" > "$HOME/.cache/television/init.$shell"
done

# Completion commands: (command args...) — last arg is the output file basename
# For zsh, completions are prefixed with _ ; for bash, they are not.
completions=(
    "chezmoi completion SHELL"
    "jj util completion SHELL"
    "atuin gen-completions --shell SHELL --out-dir OUTDIR"
    "yazi --completions SHELL"
    "zellij setup --generate-completion SHELL"
    "starship completions SHELL"
    "deno completions SHELL"
    "nh completions SHELL"
    "delta --generate-completion SHELL"
    "tv completion SHELL"
    "rustup completions SHELL"
    "rustup completions SHELL cargo"
)

for shell in zsh bash; do
    outdir="$HOME/.cache/$shell/completions"
    if [ "$shell" = "zsh" ]; then prefix="_"; else prefix=""; fi

    for entry in "${completions[@]}"; do
        # Replace SHELL placeholder
        cmd="${entry//SHELL/$shell}"

        # Skip if the tool isn't installed (first word of the command)
        tool="${cmd%% *}"
        has "$tool" || continue

        # Determine the output name (last word = tool name)
        # Special case: "rustup completions <shell> cargo" -> cargo
        name="${cmd##* }"

        # Special case: atuin uses --out-dir instead of stdout
        if [[ "$cmd" == *"--out-dir OUTDIR"* ]]; then
            cmd="${cmd//OUTDIR/$outdir}"
            $cmd 2>/dev/null || true
        else
            $cmd > "$outdir/${prefix}${name}" 2>/dev/null || true
        fi
    done
done
