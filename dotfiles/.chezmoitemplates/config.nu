const aliases_file = path self aliases.nu
source $aliases_file

const catppuccin_file = path self catppuccin.nu
source $catppuccin_file

{{- range $t := list "bat" "bootstrap" "cargo" "chezmoi-support" "claude" "curl" "gh" "gh-hide-comment" "git" "jj" "lenovo-con-mode" "man" "nix" "op" "rg" "ssh" "uv" "vscode" "zellij" "zoxide" }}
const completion_{{ $t | replace "-" "_" }} = if ((path self completions/{{ $t }}.nu) | path exists) { path self completions/{{ $t }}.nu } else { null }
source $completion_{{ $t | replace "-" "_" }}
{{- end }}

$env.config = (
    $env.config
    | upsert cursor_shape {
        vi_insert: "line"
        vi_normal: "block"
    }
    | upsert edit_mode "vi"
    | upsert buffer_editor "hx"
    | upsert highlight_resolved_externals true
    | upsert rm {
        always_trash: true
    }
    | upsert show_banner false
    | upsert use_ansi_coloring true
    | upsert use_kitty_protocol true
    | upsert history ($env.config.history? | default {} | merge {
        max_size: 10000
        sync_on_enter: true
        file_format: "plaintext"
    })
)

$env.config = ($env.config | upsert hooks {|config|
    let hooks = ($config.hooks? | default {})
    $hooks | upsert pre_prompt {|hooks|
        ($hooks.pre_prompt? | default [] | append {|| apply-system-theme })
    }
})

const atuin_init = if ("{{ .chezmoi.homeDir }}/.local/share/atuin/init.nu" | path exists) {
    "{{ .chezmoi.homeDir }}/.local/share/atuin/init.nu"
} else {
    null
}
source $atuin_init

if $atuin_init != null {
    $env.config = ($env.config | upsert keybindings {|config|
        ($config.keybindings? | default [] | append [
            {
                name: atuin
                modifier: control
                keycode: char_r
                mode: [emacs, vi_normal, vi_insert]
                event: { send: executehostcommand cmd: (_atuin_search_cmd) }
            }
        ])
    })
}

{{- if eq .chezmoi.os "darwin" }}
def --wrapped rebuild [...args] {
    ^nh darwin switch (readlink -f /etc/nixos/) ...$args
}
def --wrapped check [...args] {
    free darwin-rebuild check --flake (readlink -f /etc/nixos/) ...$args
}
def --wrapped micfix [...args] {
    free killall coreaudiod ...$args
}
{{- else }}
def --wrapped rebuild [...args] {
    free nh os switch (readlink -f /etc/nixos/) ...$args
}
def --wrapped check [...args] {
    nix flake check (readlink -f /etc/nixos/) ...$args
}
def --wrapped micfix [...args] {
    systemctl --user restart pipewire pipewire-pulse wireplumber ...$args
}
{{- end }}
