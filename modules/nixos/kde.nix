{
  config,
  pkgs,
  lib,
  ...
}:
let
  inherit (lib.attrsets) attrValues;
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.options) mkEnableOption;
in
{
  options.nixOS.kde.enable = mkEnableOption "KDE Plasma";
  options.nixOS.kde.hyperWindowTiling.enable = mkEnableOption "Hyper-key KWin window tiling script";

  config = mkMerge [
    (mkIf config.nixOS.kde.enable {
      services = {
        displayManager.sddm.enable = true;
        desktopManager.plasma6.enable = true;
      };
      environment.systemPackages = attrValues {
        inherit (pkgs.unstable.kdePackages)
          breeze
          breeze-gtk
          breeze-icons
          ffmpegthumbs
          ;
      };
    })
    (mkIf (config.nixOS.kde.enable || config.nixOS.kde.hyperWindowTiling.enable) {
      environment.systemPackages = [
        pkgs.hyper-window-tiling-kde
      ];
    })
  ];
}
