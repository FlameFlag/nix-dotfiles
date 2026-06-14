{ lib, pkgs }:

let
  userPackages = import ./user-packages.nix { inherit lib pkgs; };
in
pkgs.buildEnv {
  name = "nix-dotfiles-immutable-profile";
  paths = userPackages ++ [
    pkgs.immutable-activate
    pkgs.scaffold
    pkgs.unstable.chezmoi
    pkgs.unstable.nix
  ];

  pathsToLink = [
    "/bin"
    "/share"
  ];

  meta = {
    description = "User packages exported for nix-dotfiles immutable Linux hosts";
    platforms = lib.platforms.linux;
  };
}
