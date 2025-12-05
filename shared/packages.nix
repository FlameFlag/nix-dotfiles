{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
{
  environment.systemPackages =
    builtins.attrValues {
      # Nix Related
      inherit (pkgs.unstable)
        nil
        nixd
        nixfmt
        nixpkgs-review
        ;

      # Anything Language Related
      inherit (pkgs.unstable) bun deno;
      inherit (pkgs.unstable) zls zig;
      inherit (inputs.rust-overlay.packages.${config.nixpkgs.hostPlatform.system}) default;
      inherit (pkgs.unstable) nuget-to-json;
      inherit (pkgs.unstable.dotnetCorePackages) sdk_9_0_3xx sdk_10_0-bin;

      uutils-coreutils-noprefix = (lib.hiPrio pkgs.unstable.uutils-coreutils-noprefix);
      uutils-diffutils = (lib.hiPrio pkgs.unstable.uutils-diffutils);
      uutils-findutils = (lib.hiPrio pkgs.unstable.uutils-findutils);

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
        procs # ps
        ripgrep # grep
        sd # sed
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
      inherit (pkgs.unstable)
        ffmpeg-full
        imagemagick
        mediainfo
        ;
      inherit (pkgs)
        yt-dlp
        yt-dlp-script
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
        hyperfine
        tokei
        patch
        shellcheck
        tldr
        which
        ;
      inherit (pkgs.unstable) prettier;
    }
    ++ lib.optionals config.nixpkgs.hostPlatform.isLinux (
      builtins.attrValues {
        inherit (pkgs.unstable)
          networkmanagerapplet
          pavucontrol # PulseAudio Volume Control GUI
          playerctl # Control media players via MPRIS (CLI)
          ;

        inherit (pkgs.unstable.kdePackages) ffmpegthumbs;
        inherit (pkgs.unstable) nufraw-thumbnailer;

        inherit (pkgs.unstable.kdePackages) breeze breeze-gtk breeze-icons;
      }
    );
}
