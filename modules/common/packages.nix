{ lib, pkgs, ... }:
let
  inherit (lib.meta) hiPrio;
in
{
  environment.systemPackages =
    with pkgs;
    [
      # Dotfiles
      lsp-diagnostic-filter
      unstable.sops

      # Local/External tools
      codex-lldb-mcp
      dis
      eupkgs.agent-statusline
      eupkgs.agent-statusline-pi
      eupkgs.pi-ssh-tools
      eupkgs.web-search-pi

      # Nix
      unstable.cachix
      unstable.nh
      unstable.nil
      unstable.nix-prefetch-github
      unstable.nix-tree
      unstable.nixd
      unstable.nixfmt
      unstable.nixpkgs-review

      # Shells
      unstable.bash
      unstable.nushell
      unstable.zsh

      # Shell tools
      unstable.atuin
      unstable.fzf
      unstable.gnused
      unstable.starship
      unstable.television
      unstable.zellij
      unstable.zoxide

      # Coreutils replacements
      (hiPrio unstable.uutils-coreutils-noprefix)
      (hiPrio unstable.uutils-diffutils)
      (hiPrio unstable.uutils-findutils)

      # Rust CLI tools
      unstable.bat
      unstable.btop
      unstable.delta
      unstable.duf
      unstable.dust
      unstable.eza
      unstable.fd
      unstable.hexyl
      unstable.jujutsu
      unstable.procs
      unstable.ripgrep
      unstable.sd
      unstable.yazi

      # Editors and UI
      unstable.gitui
      unstable.helix

      # Development
      unstable.biome
      unstable.gh
      unstable.go
      unstable.golangci-lint
      unstable.gopls
      unstable.hyperfine
      unstable.git-filter-repo
      unstable.git-lfs
      unstable.nuget-to-json
      unstable.shellcheck
      unstable.sqlcipher
      unstable.zizmor
      unstable.zon2nix

      # Text and data
      unstable.jq
      unstable.less
      unstable.pandoc
      unstable.tldr
      unstable.tree

      # Networking
      unstable.clipboard-jh
      unstable.curl
      unstable.dnsutils
      unstable.netcat-gnu
      unstable.nmap
      unstable.openssh_hpn
      unstable.wget
      unstable.xh

      # System inspection
      unstable.file
      unstable.lsof
      unstable.ncdu
      unstable.pciutils
      unstable.pfetch-rs
      unstable.smartmontools
      unstable.tokei
      unstable.which

      # Media
      unstable.ffmpeg
      unstable.imagemagick
      unstable.mediainfo

      # Archives
      unstable.rar
      unstable.unrar
      unstable.unzip
      unstable.xz
      unstable.zip

      # Patching and sync
      unstable.patch
      unstable.rsync
    ]
    ++ lib.lists.optionals pkgs.stdenv.hostPlatform.isLinux [
      # Linux desktop
      unstable.ghostty
      unstable.google-chrome
      unstable.networkmanagerapplet
      unstable.nufraw-thumbnailer
      unstable.pavucontrol
      unstable.playerctl
      unstable.wl-clipboard

      # KDE integration
      unstable.kdePackages.breeze
      unstable.kdePackages.breeze-gtk
      unstable.kdePackages.breeze-icons
      unstable.kdePackages.ffmpegthumbs
    ];
}
