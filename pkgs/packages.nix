{ pkgs, lib, ... }:
let
  inherit (lib.attrsets) attrValues;
  inherit (lib.meta) hiPrio;
in
{
  environment.systemPackages =
    attrValues {
      # Dotfiles
      inherit (pkgs.unstable) sops;

      # Nix Related
      inherit (pkgs.unstable)
        nh
        nil
        nix-prefetch-github
        nixd
        nixfmt
        nixpkgs-review
        ;

      # Anything Language Related
      inherit (pkgs.unstable) nuget-to-json;
      inherit (pkgs.unstable)
        go
        golangci-lint
        gopls
        ;
      uutils-coreutils-noprefix = hiPrio pkgs.unstable.uutils-coreutils-noprefix;
      uutils-diffutils = hiPrio pkgs.unstable.uutils-diffutils;
      uutils-findutils = hiPrio pkgs.unstable.uutils-findutils;

      # Shells (No Config)
      inherit (pkgs.unstable) bash zsh;

      # Modern Rust Alternatives
      inherit (pkgs.unstable)
        bat # cat
        bottom # htop & btop
        broot # tree
        delta # difff
        duf # df
        dust # du
        eza # ls
        fd # find
        fzf # fuzzy finder
        procs # ps
        ripgrep # grep
        tv # television
        sd # sed
        television # fuzzy finder TUI
        xh # curl
        pfetch-rs # neofetch
        ;

      # TUI
      inherit (pkgs.unstable)
        btop
        ncdu
        nix-tree
        ;

      # Media
      inherit (pkgs) dis;
      inherit (pkgs.unstable)
        ffmpeg
        imagemagick
        mediainfo
        ;
      # File Management & Archiving
      inherit (pkgs.unstable)
        rar
        unrar
        unzip
        zip
        ;
      inherit (pkgs.unstable)
        pandoc
        rsync
        tree
        xz
        ;

      # Text Processing & Viewing
      inherit (pkgs.unstable)
        hexyl # CLI hex viewer
        jq # CLI JSON processor
        less
        ;

      # Networking
      inherit (pkgs.unstable)
        curl
        dnsutils # `dig`, `nslookup`, etc.
        netcat-gnu # GNU netcat
        nmap
        openssh_hpn # SSH client/server (High Performance Networking patches)
        wget
        ;

      # System Information & Monitoring
      inherit (pkgs.unstable)
        file
        lsof # List open files
        pciutils # lspci
        smartmontools # S.M.A.R.T. disk health monitoring tools
        ;

      # Misc
      inherit (pkgs.unstable)
        clipboard-jh
        gnused # GNU sed (gsed) - needed by fzf-bash-completion on macOS
        hyperfine
        patch
        shellcheck
        tldr
        tokei
        which
        ;

      inherit (pkgs.unstable)
        atuin
        gh
        gitui
        helix
        jujutsu
        nushell
        starship
        yazi
        # zed-editor
        zellij
        zoxide
        ;

    }
    ++ lib.lists.optionals pkgs.stdenv.hostPlatform.isLinux (attrValues {
      inherit (pkgs.unstable)
        ghostty
        google-chrome
        networkmanagerapplet
        pavucontrol # PulseAudio Volume Control GUI
        playerctl # Control media players via MPRIS (CLI)
        wl-clipboard
        ;

      inherit (pkgs.unstable.kdePackages) ffmpegthumbs;
      inherit (pkgs.unstable) nufraw-thumbnailer;

      inherit (pkgs.unstable.kdePackages) breeze breeze-gtk breeze-icons;
    });
}
