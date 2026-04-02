{
  pkgs,
  lib,
  config,
  inputs,
  ...
}:
{
  options.nixOS.niri.enable = lib.mkEnableOption "niri";

  config = lib.mkIf config.nixOS.niri.enable {
    programs.niri.enable = true;

    xdg.portal = {
      enable = true;
      extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
    };

    environment.systemPackages = builtins.attrValues {
      inherit (pkgs)
        wl-clipboard
        anyrun
        mako
        swaybg
        ;
      quickshell = inputs.quickshell.packages.${pkgs.stdenv.hostPlatform.system}.default;
    };
  };
}
