{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.attrsets) attrValues;
  inherit (lib.modules) mkIf;
  inherit (lib.strings) concatStringsSep;

  desktopEnabled = config.nixOS.gnome.enable || config.nixOS.kde.enable;

  chromiumFeatures = [
    "ForceEnableWebGpuInterop"
    "ReduceOpsTaskSplitting"
    "TouchpadOverscrollHistoryNavigation"
    "VaapiVideoDecoder"
    "VaapiVideoEncoder"
    "BrowsingTopics"
    "InterestGroupStorage"
  ];

  chromiumDisabledFeatures = [
    "ExtensionManifestV2Unsupported"
    "ExtensionManifestV2Disabled"
  ];

  commandLineArgs = [
    "--enable-logging=stderr"
    "--enable-features=${concatStringsSep "," chromiumFeatures}"
    "--disable-features=${concatStringsSep "," chromiumDisabledFeatures}"
    "--ignore-gpu-blocklist"
    "--enable-wayland-ime"
    "--wayland-text-input-version=3"
  ];

  heliumBrowser = pkgs.eupkgs.helium-browser.override {
    commandLineArgs = concatStringsSep " " commandLineArgs;
  };
in
{
  config = mkIf desktopEnabled {
    programs.chromium.enable = true;

    environment.systemPackages = attrValues {
      inherit heliumBrowser;

      inherit (pkgs.unstable)
        networkmanagerapplet
        nufraw-thumbnailer
        pavucontrol
        playerctl
        ;
    };
  };
}
