{ pkgs, lib, ... }:
let
  paidFonts = (pkgs.callPackage ../../pkgs/paid-fonts/build-font.nix { }).packages;
in
{
  fonts = {
    packages = builtins.attrValues paidFonts;
  };
}
