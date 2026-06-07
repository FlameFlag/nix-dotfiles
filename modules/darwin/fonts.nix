{
  config,
  pkgs,
  lib,
  ...
}:
{
  fonts = {
    packages = lib.lists.optionals config.flame.fonts.paid.enable (
      let
        paidFonts = (pkgs.callPackage ../../packages/paid-fonts/build-font.nix { }).packages;
      in
      lib.attrsets.attrValues paidFonts
    );
  };
}
