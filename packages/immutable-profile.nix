{ lib, pkgs }:

pkgs.buildEnv {
  name = "nix-dotfiles-immutable-profile";
  paths = lib.attrValues {
    inherit (pkgs)
      dis
      immutable-activate
      scaffold
      ;

    inherit (pkgs.unstable)
      atuin
      bash
      bat
      bottom
      broot
      btop
      chezmoi
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
      nix
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
      ;
  };

  pathsToLink = [
    "/bin"
    "/share"
  ];

  meta = {
    description = "User packages exported for nix-dotfiles immutable Linux hosts";
    platforms = lib.platforms.linux;
  };
}
