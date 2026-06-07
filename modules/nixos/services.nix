{
  config,
  lib,
  pkgs,
  ...
}:
let
  paidFonts = (pkgs.callPackage ../../packages/paid-fonts/build-font.nix { }).packages;
in
{
  services = {
    kmscon = {
      enable = true;
      hwRender = true;
      useXkbConfig = true;
      extraOptions = "--term xterm-256color";
      fonts = lib.mkIf config.flame.fonts.paid.enable [
        {
          name = "TX-02 Nerd Font";
          package = paidFonts.tx-02;
        }
      ];
    };

    libinput.enable = true;
    openssh.enable = true;
    xserver.xkb.layout = "us";
  };
}
