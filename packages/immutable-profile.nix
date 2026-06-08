{ lib, pkgs }:

pkgs.buildEnv {
  name = "nix-dotfiles-immutable-profile";
  paths =
    (with pkgs; [
      dis
    ])
    ++ (with pkgs.unstable; [
      atuin
      bash
      bat
      bottom
      broot
      btop
      delta
      duf
      dust
      eza
      fd
      fzf
      git
      gitui
      helix
      jq
      jujutsu
      less
      nh
      nil
      nix-prefetch-github
      nix-tree
      nixd
      nixfmt
      nushell
      ripgrep
      sd
      starship
      television
      yazi
      zellij
      zoxide
      zsh
    ]);

  pathsToLink = [
    "/bin"
    "/share"
  ];

  meta = {
    description = "User packages exported from the nix-dotfiles immutable Distrobox";
    platforms = lib.platforms.linux;
  };
}
