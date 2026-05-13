{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.flame.packages.profiles;

  enabledOption =
    description:
    lib.mkOption {
      type = lib.types.bool;
      default = true;
      inherit description;
    };

  gitWithEmailValid = pkgs.unstable.git.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      sed -i "s|export GITPERLLIB='\(.*\)'|export GITPERLLIB='\1:${
        pkgs.unstable.perlPackages.makePerlPath [ pkgs.unstable.perlPackages.EmailValid ]
      }'|" \
        $out/libexec/git-core/git-send-email
    '';
  });

  basePackages = [
    (lib.hiPrio pkgs.unstable.uutils-coreutils-noprefix)
    (lib.hiPrio pkgs.unstable.uutils-diffutils)
    (lib.hiPrio pkgs.unstable.uutils-findutils)
    gitWithEmailValid
  ]
  ++ (with pkgs.unstable; [
    atuin
    bash
    bat
    btop
    cachix
    chezmoi
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
    pkgs.gh-hide-comment
    pkgs.ziglint
    pkgs.eupkgs.web-search-pi
  ]
  ++ (with pkgs.unstable; [
    bun
    deno
    go
    golangci-lint
    gopls
    hyperfine
    git-filter-repo
    git-lfs
    nix-prefetch-github
    nixpkgs-review
    nodejs_25
    nuget-to-json
    pciutils
    pfetch-rs
    prettier
    ruff
    rustup
    sqlcipher
    smartmontools
    tree
    ty
    uv
    zig
    zig-shell-completions
    zls
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
  ])
  ++ (with pkgs.eupkgs; [
    yt-dlp
    yt-dlp-script
  ]);

  archivePackages = with pkgs.unstable; [
    rar
    unrar
    unzip
    zip
  ];

  guiPackages = with pkgs.unstable; [
    gitui
    vscode
  ];

  linuxDesktopPackages =
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
    ]);
in
{
  options.flame.packages.profiles = {
    base = enabledOption "Install baseline shell, editor, Nix, network, and system tools.";
    dev = enabledOption "Install language toolchains and development utilities.";
    media = enabledOption "Install media download, conversion, and inspection tools.";
    archive = enabledOption "Install archive/compression utilities.";
    gui = enabledOption "Install cross-platform GUI/TUI applications.";
    linuxDesktop = lib.mkOption {
      type = lib.types.bool;
      default = pkgs.stdenv.hostPlatform.isLinux;
      description = "Install Linux desktop integration packages.";
    };
  };

  config.environment.systemPackages =
    lib.optionals cfg.base basePackages
    ++ lib.optionals cfg.dev devPackages
    ++ lib.optionals cfg.media mediaPackages
    ++ lib.optionals cfg.archive archivePackages
    ++ lib.optionals cfg.gui guiPackages
    ++ lib.optionals cfg.linuxDesktop linuxDesktopPackages;
}
