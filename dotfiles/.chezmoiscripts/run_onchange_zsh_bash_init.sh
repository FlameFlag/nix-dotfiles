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

# Generate init files for zsh
starship init zsh > "$HOME/.cache/starship/init.zsh"
zoxide init zsh --cmd cd > "$HOME/.cache/zoxide/init.zsh"
atuin init zsh --disable-up-arrow > "$HOME/.cache/atuin/init.zsh"
tv init zsh > "$HOME/.cache/television/init.zsh"

# Generate init files for bash
starship init bash > "$HOME/.cache/starship/init.bash"
zoxide init bash --cmd cd > "$HOME/.cache/zoxide/init.bash"
atuin init bash --disable-up-arrow > "$HOME/.cache/atuin/init.bash"
tv init bash > "$HOME/.cache/television/init.bash"

# Generate zsh completions
chezmoi completion zsh > "$HOME/.cache/zsh/completions/_chezmoi" 2>/dev/null || true
jj util completion zsh > "$HOME/.cache/zsh/completions/_jj" 2>/dev/null || true
atuin gen-completions --shell zsh --out-dir "$HOME/.cache/zsh/completions" 2>/dev/null || true
yazi --completions zsh > "$HOME/.cache/zsh/completions/_yazi" 2>/dev/null || true
zellij setup --generate-completion zsh > "$HOME/.cache/zsh/completions/_zellij" 2>/dev/null || true
starship completions zsh > "$HOME/.cache/zsh/completions/_starship" 2>/dev/null || true
deno completions zsh > "$HOME/.cache/zsh/completions/_deno" 2>/dev/null || true
nh completions zsh > "$HOME/.cache/zsh/completions/_nh" 2>/dev/null || true
delta --generate-completion zsh > "$HOME/.cache/zsh/completions/_delta" 2>/dev/null || true
tv completion zsh > "$HOME/.cache/zsh/completions/_tv" 2>/dev/null || true
rustup completions zsh > "$HOME/.cache/zsh/completions/_rustup" 2>/dev/null || true
rustup completions zsh cargo > "$HOME/.cache/zsh/completions/_cargo" 2>/dev/null || true

# Generate bash completions
chezmoi completion bash > "$HOME/.cache/bash/completions/chezmoi" 2>/dev/null || true
jj util completion bash > "$HOME/.cache/bash/completions/jj" 2>/dev/null || true
atuin gen-completions --shell bash --out-dir "$HOME/.cache/bash/completions" 2>/dev/null || true
yazi --completions bash > "$HOME/.cache/bash/completions/yazi" 2>/dev/null || true
zellij setup --generate-completion bash > "$HOME/.cache/bash/completions/zellij" 2>/dev/null || true
starship completions bash > "$HOME/.cache/bash/completions/starship" 2>/dev/null || true
deno completions bash > "$HOME/.cache/bash/completions/deno" 2>/dev/null || true
nh completions bash > "$HOME/.cache/bash/completions/nh" 2>/dev/null || true
delta --generate-completion bash > "$HOME/.cache/bash/completions/delta" 2>/dev/null || true
tv completion bash > "$HOME/.cache/bash/completions/tv" 2>/dev/null || true
rustup completions bash > "$HOME/.cache/bash/completions/rustup" 2>/dev/null || true
rustup completions bash cargo > "$HOME/.cache/bash/completions/cargo" 2>/dev/null || true
