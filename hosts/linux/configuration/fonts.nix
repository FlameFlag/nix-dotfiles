{
  config,
  lib,
  pkgs,
  ...
}:
{
  fonts = {
    fontconfig.defaultFonts.monospace = [ "TX-02 Nerd Font" ];
    packages = lib.lists.optionals config.flame.fonts.paid.enable (
      let
        paidFonts = (pkgs.callPackage ../../../packages/paid-fonts/build-font.nix { }).packages;
      in
      lib.attrsets.attrValues paidFonts
    );
  };
}
