{
  includeLinuxDesktop ? false,
  lib,
  pkgs,
}:
let
  inherit (lib.meta) hiPrio;
in
(with pkgs; [
  lldb-mcp-launcher
  dis
  eupkgs.agent-statusline
  eupkgs.agent-statusline-pi
  eupkgs.catppuccin-system-theme-pi
  eupkgs.pi-ssh-tools
  eupkgs.web-search-pi
  (hiPrio unstable.uutils-coreutils-noprefix)
  (hiPrio unstable.uutils-diffutils)
  (hiPrio unstable.uutils-findutils)
])
++ (with pkgs.unstable; [
  atuin
  bash
  bat
  biome
  bottom
  broot
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
  ffmpeg
  file
  fzf
  gcc
  gh
  git
  git-filter-repo
  git-lfs
  gitui
  gnused
  go
  golangci-lint
  gopls
  gnumake
  helix
  hexyl
  hyperfine
  imagemagick
  jq
  jujutsu
  less
  lsof
  mediainfo
  ncdu
  netcat-gnu
  nh
  nil
  nix-prefetch-github
  nix-tree
  nixd
  nixfmt
  nixpkgs-review
  nmap
  nuget-to-json
  nushell
  openssh_hpn
  pandoc
  patch
  pciutils
  pkg-config
  pfetch-rs
  prettier
  procs
  rar
  ripgrep
  rsync
  sd
  shellcheck
  smartmontools
  sops
  sqlcipher
  starship
  television
  tldr
  tokei
  tree
  unzip
  wget
  which
  xh
  xz
  yazi
  zellij
  zizmor
  zip
  zoxide
  zon2nix
  zsh
])
++ lib.lists.optionals pkgs.stdenv.hostPlatform.isLinux (
  with pkgs.unstable;
  [
    wl-clipboard
  ]
)
++ lib.lists.optionals (includeLinuxDesktop && pkgs.stdenv.hostPlatform.isLinux) (
  (with pkgs.unstable; [
    google-chrome
    networkmanagerapplet
    nufraw-thumbnailer
    pavucontrol
    playerctl
  ])
  ++ (with pkgs.unstable.kdePackages; [
    breeze
    breeze-gtk
    breeze-icons
    ffmpegthumbs
  ])
)
