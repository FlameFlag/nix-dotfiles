{ lib, pkgs, ... }:
{
  environment.systemPackages = (
    lib.attrsets.attrValues {
      inherit (pkgs) bootstrap;
      inherit (pkgs) telegram-desktop;
      inherit (pkgs.unstable) jq;
    }
  );
}
