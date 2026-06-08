{ lib, pkgs, ... }:
{
  environment.systemPackages = (
    lib.attrsets.attrValues {
      inherit (pkgs) scaffold;
      inherit (pkgs) telegram-desktop;
      inherit (pkgs.unstable) jq;
    }
  );
}
