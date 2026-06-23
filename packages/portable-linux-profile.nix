{
  includePaidFonts ? true,
  lib,
  pkgs,
}:

let
  paidFonts = (pkgs.callPackage ./paid-fonts/build-font.nix { }).packages;
  userPackages = import ./user-packages.nix { inherit lib pkgs; };
in
pkgs.buildEnv {
  name = "nix-dotfiles-portable-linux-profile";
  paths =
    userPackages
    ++ lib.optionals includePaidFonts (lib.attrsets.attrValues paidFonts)
    ++ [
      pkgs.immutable-activate
      pkgs.kanata-with-cmd
      pkgs.ansible
      pkgs.unstable.chezmoi
      pkgs.unstable.nix
    ];

  pathsToLink = [
    "/bin"
    "/share"
  ];

  meta = {
    description = "User packages exported for nix-dotfiles portable Linux hosts";
    platforms = lib.platforms.linux;
  };
}
