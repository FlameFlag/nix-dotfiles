alias v = hx
alias vi = hx
alias vim = hx
alias h = hx

alias l = ls
alias ll = ls
alias cat = open
alias btop = zellij-theme-run btop
alias htop = zellij-theme-run btop
alias top = zellij-theme-run btop
alias neofetch = pfetch

alias m4a = yt-dlp-script m4a
alias m4a-cut = yt-dlp-script m4a-cut
alias mp3 = yt-dlp-script mp3
alias mp3-cut = yt-dlp-script mp3-cut
alias mp4 = yt-dlp-script mp4
alias mp4-cut = yt-dlp-script mp4-cut

alias cc = claude --allow-dangerously-skip-permissions
alias oo = opencode

def command-path [command: string]: nothing -> any {
    which $command | get path | first
}

def --wrapped free [...args] {
    let runner = (command-path system-runner)
    if ($runner == null) {
        error make { msg: "free: system-runner is not installed yet; install system-run-mcp first" }
    }

    ^sudo -n $runner ...$args
}

def --wrapped f [...args] {
    free ...$args
}

def --wrapped cx [...args] {
    zellij-theme-run codex ...$args
}

def --wrapped cxg [...args] {
    zellij-theme-run codex -c mcp_servers.ghidra.enabled=true -c mcp_servers.lldb.enabled=true ...$args
}

def nix-dotfiles-flake []: nothing -> path {
    let configured = ($env.NIX_DOTFILES_FLAKE? | default null)
    if ($configured | is-not-empty) {
        return ($configured | path expand)
    }

    let os_name = (try { ^uname -s } catch { "" })
    let candidates = if $os_name == "Darwin" {
        [
            ([$nu.home-dir "Developer" "nix-dotfiles"] | path join)
            ([$nu.home-dir "nix-dotfiles"] | path join)
            "/etc/nixos"
        ]
    } else {
        [
            ([$nu.home-dir "nix-dotfiles"] | path join)
            "/etc/nixos"
        ]
    }

    for candidate in $candidates {
        if ([$candidate "flake.nix"] | path join | path exists) {
            return ($candidate | path expand)
        }
    }

    "/etc/nixos" | path expand
}

def is-immutable-wrapper [candidate: path]: nothing -> bool {
    let text = try {
        open --raw $candidate
    } catch {
        ""
    }
    $text | str contains "# nix-dotfiles: immutable-wrapper"
}

def is-immutable-nix-host []: nothing -> bool {
    let nix_path = (command-path nix)
    if ($nix_path == null) {
        return false
    }

    is-immutable-wrapper $nix_path
}

def is-portable-nix-host []: nothing -> bool {
    if (is-immutable-nix-host) {
        return true
    }

    not ("/etc/NIXOS" | path exists)
}

def --wrapped update [...args] {
    let flake = (nix-dotfiles-flake)
    if $nu.os-info.name == "macos" {
        ^nix flake update --flake $flake ...$args
    } else if (is-portable-nix-host) {
        ^nix run $"($flake)#immutable-activate" -- --flake $flake --update --host-update ...$args
    } else {
        ^nix flake update --flake $flake ...$args
    }
}

def --wrapped rebuild [...args] {
    let flake = (nix-dotfiles-flake)
    if $nu.os-info.name == "macos" {
        ^nh darwin switch $flake ...$args
    } else if (is-portable-nix-host) {
        ^nix run $"($flake)#immutable-activate" -- --flake $flake ...$args
    } else {
        free nh os switch $flake ...$args
    }
}

def --wrapped check [...args] {
    let flake = (nix-dotfiles-flake)
    if $nu.os-info.name == "macos" {
        free darwin-rebuild check --flake $flake ...$args
    } else {
        ^nix flake check $flake ...$args
        if (is-portable-nix-host) {
            ^nix build $"($flake)#immutable-profile"
        }
    }
}

alias cza = chezmoi apply --force
alias cd = z
alias dc = z

def --env yy [...args]: nothing -> nothing {
    let tmp = (mktemp --tmpdir "yazi-cwd.XXXXX")
    ^yazi ...$args --cwd-file $tmp
    let cwd = if ($tmp | path exists) {
        open --raw $tmp | str trim
    } else {
        ""
    }
    rm --force --permanent $tmp

    if $cwd != "" and $cwd != $env.PWD {
        cd $cwd
    }
}

def history-sync [
    --limit: int = 10000
] {
    ^atuin search --limit $limit --format "{command}" | save --force --raw $nu.history-path
}

def nix-build-file [
    file: path,
    args: string = "{}"
] {
    ^nix-build -E $"with import <nixpkgs> {}; callPackage ($file | path expand) ($args)"
}

def clean-roots [] {
    let paths_to_delete = (^nix-store --gc --print-roots
        | lines
        | where { |line| $line !~ '^(/nix/var|/run/\w+-system|\{|/proc)' }
        | where { |line| $line !~ '\b(home-manager|flake-registry\.json)\b' }
        | parse --regex '^(?P<path>\S+)'
        | get path)

    if ($paths_to_delete | is-empty) {
        print "Nothing to clean"
        return
    }

    print "Cleaning roots..."
    let results = for $path in $paths_to_delete {
        try {
            ^unlink $path
            { path: $path, status: "Deleted" }
        } catch { |e|
            { path: $path, status: $"Error: `($e.msg)`" }
        }
    }

    if not ($results | is-empty) {
        $results | table
    }
    print "Done"
}

def --wrapped python [...args] { uv run python ...$args }
def --wrapped python3 [...args] { uv run python3 ...$args }

def ensure-uv-venv []: nothing -> nothing {
    let venv = ($env.VIRTUAL_ENV? | default null)
    if ($venv | is-empty) and not (["." ".venv"] | path join | path exists) {
        ^uv venv --quiet
    }
}

def --wrapped pip [...rest] {
    ensure-uv-venv
    ^uv pip ...$rest
}

def --wrapped pip3 [...rest] {
    ensure-uv-venv
    ^uv pip ...$rest
}

def now [] { date now | format date "%H:%M:%S" }
def nowdate [] { date now | format date "%d-%m-%Y" }
def nowunix [] { date now | format date "%s" }
def xdg-data-dirs [] { $env.XDG_DATA_DIRS? | default "" | split row (char esep) | compact --empty | enumerate }
