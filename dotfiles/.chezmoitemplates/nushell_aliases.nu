alias v = hx
alias vi = hx
alias vim = hx
alias h = hx

alias l = ls
alias ll = ls
alias cat = open
alias htop = btop
alias neofetch = pfetch

alias m4a = yt-dlp-script m4a
alias m4a-cut = yt-dlp-script m4a-cut
alias mp3 = yt-dlp-script mp3
alias mp3-cut = yt-dlp-script mp3-cut
alias mp4 = yt-dlp-script mp4
alias mp4-cut = yt-dlp-script mp4-cut

alias update = nix flake update --flake (readlink -f /etc/nixos/)

alias cd = __zoxide_z
alias dc = __zoxide_z

def --env yy [...args] {
    let tmp = (mktemp -t "yazi-cwd.XXXXX")
    ^yazi ...$args --cwd-file $tmp
    let cwd = (open $tmp)
    if $cwd != "" and $cwd != $env.PWD {
        cd $cwd
    }
    rm -fp $tmp
}

def history-sync [] {
    let atuin_history = (
        ^atuin search --limit 10000 --format "{command}" 
        | lines
    )
    $atuin_history | save -f $nu.history-path
}
history-sync

def nix-build-file [
    file: string,
    args: string = "{}"
] {
    nix-build -E $"with import <nixpkgs> {}; callPackage ($file | path expand) ($args)"
}

def clean-roots [] {
    let $paths_to_delete = (nix-store --gc --print-roots
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
    let $results = for $path in $paths_to_delete {
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

def now [] { date now | format date "%H:%M:%S" }
def nowdate [] { date now | format date "%d-%m-%Y" }
def nowunix [] { date now | format date "%s" }
def xdg-data-dirs [] { echo $env.XDG_DATA_DIRS | str replace -a : "\n" | lines | enumerate }
