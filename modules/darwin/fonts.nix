{
  config,
  pkgs,
  lib,
  ...
}:
{
  fonts = {
    packages = lib.optionals config.flame.fonts.paid.enable (
      let
        paidFonts = (pkgs.callPackage ../../pkgs/paid-fonts/build-font.nix { }).packages;
      in
      builtins.attrValues paidFonts
    );
  };
}
