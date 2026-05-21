{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.meta) hiPrio;
  inherit (lib.options) mkOption;
  inherit (lib.types) bool;

  cfg = config.flame.packages.profiles;

  enabledOption = (
    description:
    mkOption {
      type = bool;
      default = true;
      inherit description;
    }
  );

  basePackages = [
    (hiPrio pkgs.unstable.uutils-coreutils-noprefix)
    (hiPrio pkgs.unstable.uutils-diffutils)
    (hiPrio pkgs.unstable.uutils-findutils)
  ]
  ++ (with pkgs.unstable; [
    atuin
    bash
    bat
    btop
    cachix
    clipboard-jh
    curl
    delta
    dnsutils
    duf
    dust
    eza
    fd
    file
    fzf
    gh
    gnused
    helix
    hexyl
    jq
    jujutsu
    less
    lsof
    ncdu
    netcat-gnu
    nh
    nil
    nix-tree
    nixd
    nixfmt
    nmap
    nushell
    openssh_hpn
    patch
    procs
    ripgrep
    rsync
    sd
    shellcheck
    sops
    starship
    television
    tldr
    tokei
    which
    wget
    xh
    xz
    yazi
    zellij
    zoxide
    zsh
  ]);

  devPackages = [
    pkgs.eupkgs.agent-statusline
    pkgs.eupkgs.agent-statusline-pi
    pkgs.eupkgs.pi-ssh-tools
    pkgs.eupkgs.web-search-pi
  ]
  ++ (with pkgs.unstable; [
    go
    golangci-lint
    gopls
    hyperfine
    git-filter-repo
    git-lfs
    nix-prefetch-github
    nixpkgs-review
    nuget-to-json
    pciutils
    pfetch-rs
    prettier
    sqlcipher
    smartmontools
    tree
    zon2nix
  ]);

  mediaPackages = [
    pkgs.dis
  ]
  ++ (with pkgs.unstable; [
    ffmpeg
    imagemagick
    mediainfo
    pandoc
  ]);

  archivePackages = with pkgs.unstable; [
    rar
    unrar
    unzip
    zip
  ];

  guiPackages = with pkgs.unstable; [
    gitui
  ];

  linuxDesktopPackages = (
    (with pkgs.unstable; [
      ghostty
      google-chrome
      networkmanagerapplet
      nufraw-thumbnailer
      pavucontrol
      playerctl
      wl-clipboard
    ])
    ++ (with pkgs.unstable.kdePackages; [
      breeze
      breeze-gtk
      breeze-icons
      ffmpegthumbs
    ])
  );
in
{
  options.flame.packages.profiles = {
    base = enabledOption "Install baseline shell, editor, Nix, network, and system tools.";
    dev = enabledOption "Install language toolchains and development utilities.";
    media = enabledOption "Install media download, conversion, and inspection tools.";
    archive = enabledOption "Install archive/compression utilities.";
    gui = enabledOption "Install cross-platform GUI/TUI applications.";
    linuxDesktop = mkOption {
      type = bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      description = "Install Linux desktop integration packages.";
    };
  };

  config.environment.systemPackages = (
    lib.lists.concatMap (profile: lib.lists.optionals profile.enable profile.packages) [
      {
        enable = cfg.base;
        packages = basePackages;
      }
      {
        enable = cfg.dev;
        packages = devPackages;
      }
      {
        enable = cfg.media;
        packages = mediaPackages;
      }
      {
        enable = cfg.archive;
        packages = archivePackages;
      }
      {
        enable = cfg.gui;
        packages = guiPackages;
      }
      {
        enable = cfg.linuxDesktop;
        packages = linuxDesktopPackages;
      }
    ]
  );
}
