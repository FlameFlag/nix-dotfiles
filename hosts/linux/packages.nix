{ lib, pkgs, ... }:
{
  environment.systemPackages = (
    lib.attrsets.attrValues {
      inherit (pkgs) telegram-desktop;
      inherit (pkgs.unstable) jq;
    }
  );
}
