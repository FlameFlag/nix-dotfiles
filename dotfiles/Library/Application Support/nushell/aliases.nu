alias v = hx
alias vi = hx
alias vim = hx
alias h = hx

alias l = ls
alias ll = ls
alias cat = open
alias htop = btop
alias top = btop
alias neofetch = pfetch

alias m4a = yt-dlp-script m4a
alias m4a-cut = yt-dlp-script m4a-cut
alias mp3 = yt-dlp-script mp3
alias mp3-cut = yt-dlp-script mp3-cut
alias mp4 = yt-dlp-script mp4
alias mp4-cut = yt-dlp-script mp4-cut

alias cc = claude --allow-dangerously-skip-permissions
alias oo = opencode
alias cx = codex-zellij-theme --dangerously-bypass-approvals-and-sandbox --dangerously-bypass-hook-trust

alias update = nix flake update --flake (readlink -f /etc/nixos/)

alias cza = chezmoi apply --force
alias dc = cd

def --env yy [...args] {
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
    nix-build -E $"with import <nixpkgs> {}; callPackage ($file | path expand) ($args)"
}

def clean-roots [] {
    let paths_to_delete = (nix-store --gc --print-roots
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
def --wrapped pip [...rest] {
    if ($env.VIRTUAL_ENV? | is-empty) and not (["." ".venv"] | path join | path exists) {
        uv venv -q
    }
    uv pip ...$rest
}
def --wrapped pip3 [...rest] {
    if ($env.VIRTUAL_ENV? | is-empty) and not (["." ".venv"] | path join | path exists) {
        uv venv -q
    }
    uv pip ...$rest
}

def now [] { date now | format date "%H:%M:%S" }
def nowdate [] { date now | format date "%d-%m-%Y" }
def nowunix [] { date now | format date "%s" }
def xdg-data-dirs [] { $env.XDG_DATA_DIRS? | default "" | split row (char esep) | compact --empty | enumerate }
