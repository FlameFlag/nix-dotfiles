{
  inputs,
  pkgs,
  pkgsUnstable,
  lib,
  config,
  ...
}:
{
  environment.systemPackages =
    builtins.attrValues {
      # Nix Related
      inherit (pkgsUnstable) nil nixd;
      inherit (pkgs) nixfmt-rfc-style nixpkgs-review;

      # Rust re-implementations of coreutils
      inherit (pkgsUnstable)
        uutils-coreutils-noprefix
        uutils-diffutils
        uutils-findutils
        ;

      # Shells (No Config)
      inherit (pkgs) bash zsh;

      # Rust
      inherit (inputs.rust-overlay.packages.${config.nixpkgs.hostPlatform.system}) default;

      # .NET
      inherit (pkgs) nuget-to-nix;
      inherit (pkgs.dotnetCorePackages) sdk_9_0_3xx sdk_10_0-bin;

      # Modern Rust Alternatives
      inherit (pkgs)
        bat # cat
        bottom # htop & btop
        broot # tree
        delta # difff
        duf # df
        dust # du
        eza # ls
        fd # find
        procs # ps
        ripgrep # grep
        sd # sed
        xh # curl
        ;

      # TUI
      inherit (pkgs)
        btop
        ncdu
        nix-tree
        ;

      # Media
      inherit (pkgs)
        ffmpeg-full
        imagemagick
        mediainfo
        yt-dlp
        yt-dlp-script
        ;

      # File Management & Archiving
      inherit (pkgs)
        rar
        unrar
        unzip
        zip
        ;
      inherit (pkgs)
        pandoc
        rsync
        tree
        xz
        ;

      # Text Processing & Viewing
      inherit (pkgs)
        hexyl # CLI hex viewer
        jq # CLI JSON processor
        less
        ;

      # Networking
      inherit (pkgs)
        curl
        dnsutils # `dig`, `nslookup`, etc.
        netcat-gnu # GNU netcat
        nmap
        openssh_hpn # SSH client/server (High Performance Networking patches)
        wget
        ;

      # System Information & Monitoring
      inherit (pkgs)
        file
        lsof # List open files
        pciutils # lspci
        smartmontools # S.M.A.R.T. disk health monitoring tools
        ;

      # Misc
      inherit (pkgs)
        hyperfine
        tokei
        patch
        shellcheck
        tldr
        which
        ;
      inherit (pkgsUnstable)
        prettier
        ;
    }
    ++ lib.optionals config.nixpkgs.hostPlatform.isLinux (
      builtins.attrValues {
        inherit (pkgs)
          networkmanagerapplet
          pavucontrol # PulseAudio Volume Control GUI
          playerctl # Control media players via MPRIS (CLI)
          ;

        inherit (pkgs.kdePackages) ffmpegthumbs;
        inherit (pkgs) nufraw-thumbnailer;

        inherit (pkgs.kdePackages) breeze breeze-gtk breeze-icons;
      }
    );
}
