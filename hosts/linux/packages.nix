{ pkgs, ... }:
{
  environment.systemPackages = builtins.attrValues {
    inherit (pkgs) telegram-desktop;
    inherit (pkgs.unstable) jq;
  };
}
