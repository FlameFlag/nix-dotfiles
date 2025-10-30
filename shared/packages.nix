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
      inherit (pkgsUnstable)
        nil
        nixd
        nixfmt
        nixpkgs-review
        ;

      uutils-coreutils-noprefix = (lib.hiPrio pkgsUnstable.uutils-coreutils-noprefix);
      uutils-diffutils = (lib.hiPrio pkgsUnstable.uutils-diffutils);
      uutils-findutils = (lib.hiPrio pkgsUnstable.uutils-findutils);

      # Shells (No Config)
      inherit (pkgsUnstable) bash zsh;

      # Rust
      inherit (inputs.rust-overlay.packages.${config.nixpkgs.hostPlatform.system}) default;

      # .NET
      inherit (pkgsUnstable) nuget-to-json;
      inherit (pkgsUnstable.dotnetCorePackages) sdk_9_0_3xx sdk_10_0-bin;

      # Modern Rust Alternatives
      inherit (pkgsUnstable)
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
        pfetch-rs # neofetch
        ;

      # TUI
      inherit (pkgsUnstable)
        btop
        ncdu
        nix-tree
        ;

      # Media
      inherit (pkgsUnstable)
        ffmpeg-full
        imagemagick
        mediainfo
        yt-dlp
        ;
      inherit (pkgs) yt-dlp-script;

      # File Management & Archiving
      inherit (pkgsUnstable)
        rar
        unrar
        unzip
        zip
        ;
      inherit (pkgsUnstable)
        pandoc
        rsync
        tree
        xz
        ;

      # Text Processing & Viewing
      inherit (pkgsUnstable)
        hexyl # CLI hex viewer
        jq # CLI JSON processor
        less
        ;

      # Networking
      inherit (pkgsUnstable)
        curl
        dnsutils # `dig`, `nslookup`, etc.
        netcat-gnu # GNU netcat
        nmap
        openssh_hpn # SSH client/server (High Performance Networking patches)
        wget
        ;

      # System Information & Monitoring
      inherit (pkgsUnstable)
        file
        lsof # List open files
        pciutils # lspci
        smartmontools # S.M.A.R.T. disk health monitoring tools
        ;

      # Misc
      inherit (pkgsUnstable)
        hyperfine
        tokei
        patch
        shellcheck
        tldr
        which
        ;
      inherit (pkgsUnstable) prettier;
    }
    ++ lib.optionals config.nixpkgs.hostPlatform.isLinux (
      builtins.attrValues {
        inherit (pkgsUnstable)
          networkmanagerapplet
          pavucontrol # PulseAudio Volume Control GUI
          playerctl # Control media players via MPRIS (CLI)
          ;

        inherit (pkgsUnstable.kdePackages) ffmpegthumbs;
        inherit (pkgsUnstable) nufraw-thumbnailer;

        inherit (pkgsUnstable.kdePackages) breeze breeze-gtk breeze-icons;
      }
    );
}
