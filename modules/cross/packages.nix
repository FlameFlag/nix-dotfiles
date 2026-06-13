{ lib, pkgs, ... }:
let
  inherit (lib.attrsets) attrValues;
  inherit (lib.meta) hiPrio;
in
{
  environment.systemPackages = attrValues {
    # Personal packages
    inherit (pkgs)
      dis
      lldb-mcp-launcher
      ;
    inherit (pkgs.eupkgs)
      agent-statusline
      agent-statusline-pi
      catppuccin-system-theme-pi
      pi-ssh-tools
      web-search-pi
      ;

    # Nix
    inherit (pkgs.unstable)
      cachix
      nh
      nil
      nix-prefetch-github
      nix-tree
      nixd
      nixfmt
      nixpkgs-review
      ;

    # Shells and prompts
    inherit (pkgs.unstable)
      atuin
      bash
      nushell
      starship
      zoxide
      zsh
      ;

    # CLI replacements
    inherit (pkgs.unstable)
      bat
      bottom
      broot
      delta
      duf
      dust
      eza
      fd
      procs
      ripgrep
      sd
      xh
      ;
    uutils-coreutils-noprefix = hiPrio pkgs.unstable.uutils-coreutils-noprefix;
    uutils-diffutils = hiPrio pkgs.unstable.uutils-diffutils;
    uutils-findutils = hiPrio pkgs.unstable.uutils-findutils;

    # Development
    inherit (pkgs.unstable)
      biome
      gcc
      gh
      git
      git-filter-repo
      git-lfs
      gitui
      go
      golangci-lint
      gopls
      gnumake
      jujutsu
      patch
      pkg-config
      prettier
      shfmt
      shellcheck
      sqlcipher
      zizmor
      ;

    # Editors and terminals
    inherit (pkgs.unstable)
      helix
      yazi
      zellij
      ;

    # File management and archives
    inherit (pkgs.unstable)
      file
      rar
      rsync
      tree
      unzip
      xz
      zip
      ;

    # Media and documents
    inherit (pkgs.unstable)
      ffmpeg
      imagemagick
      mediainfo
      pandoc
      ;

    # Networking
    inherit (pkgs.unstable)
      curl
      dnsutils
      netcat-gnu
      nmap
      openssh_hpn
      wget
      ;

    # Text processing and viewing
    inherit (pkgs.unstable)
      hexyl
      jq
      less
      ;

    # System and misc
    inherit (pkgs.unstable)
      btop
      clipboard-jh
      fzf
      gnused
      hyperfine
      lsof
      ncdu
      pfetch-rs
      sops
      television
      tldr
      tokei
      which
      ;
  };
}
