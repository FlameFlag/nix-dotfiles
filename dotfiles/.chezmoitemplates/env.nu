use std/config "env-conversions"
use std/util "path add"

$env.EDITOR = "hx"
$env.VISUAL = "hx"

path add ([ .bun .npm .local .cargo .go .yarn ] | each {|dir| [$nu.home-dir $dir bin] | path join })
if ("/run/wrappers/bin" | path exists) {
    $env.PATH = (
        ["/run/wrappers/bin"]
        | append ($env.PATH | where {|dir| $dir != "/run/wrappers/bin" })
    )
}

if ($env.TERM? == "xterm-ghostty") {
    let ghostty_terminfo = (infocmp xterm-ghostty | complete)
    if $ghostty_terminfo.exit_code != 0 {
        $env.TERM = "xterm-256color"
    }
}

if (which starship | is-not-empty) {
    $env.TRANSIENT_PROMPT_COMMAND = {|| ^starship module character }
    $env.TRANSIENT_PROMPT_COMMAND_RIGHT = {|| ^starship module time }
}

$env.TRANSIENT_PROMPT_INDICATOR = ""
$env.TRANSIENT_PROMPT_INDICATOR_VI_INSERT = ""
$env.TRANSIENT_PROMPT_INDICATOR_VI_NORMAL = ""
$env.TRANSIENT_PROMPT_MULTILINE_INDICATOR = ""

hide-env --ignore-errors NO_COLOR
$env.COLORTERM = "truecolor"
$env.LESS = "-R"
$env.ENV_CONVERSIONS = ($env.ENV_CONVERSIONS? | default {} | merge (env-conversions))

const starship_init = if ("{{ .chezmoi.homeDir }}/.cache/starship/init.nu" | path exists) {
    "{{ .chezmoi.homeDir }}/.cache/starship/init.nu"
} else {
    null
}
source $starship_init

const zoxide_init = if ("{{ .chezmoi.homeDir }}/.cache/zoxide/init.nu" | path exists) {
    "{{ .chezmoi.homeDir }}/.cache/zoxide/init.nu"
} else {
    null
}
source $zoxide_init

$env.ATUIN_NOBIND = true

{{- if eq .chezmoi.os "darwin" }}
let onepassword_ssh_auth_sock = ([$nu.home-dir "Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"] | path join)
{{- else }}
let onepassword_ssh_auth_sock = ([$nu.home-dir ".1password/agent.sock"] | path join)
{{- end }}
if ($env.SSH_CONNECTION? == null) {
    $env.SSH_AUTH_SOCK = $onepassword_ssh_auth_sock
}

# Shadow system python
$env.UV_PYTHON_PREFERENCE = "only-managed"
