{ pkgs, lib, ... }:
let
  paidFonts = (pkgs.callPackage ../../pkgs/paid-fonts/build-font.nix { }).packages;
in
{
  fonts = {
    packages =
      builtins.attrValues {
        UbuntuMono = pkgs.nerd-fonts.ubuntu-mono;
        FiraCode = pkgs.nerd-fonts.fira-code;
        Monaspace = pkgs.nerd-fonts.monaspace;
        Noto = pkgs.nerd-fonts.noto;
      }
      ++ builtins.attrValues paidFonts;
  };
}
