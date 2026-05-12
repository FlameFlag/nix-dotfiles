{ pkgs, ... }:
{
  environment.systemPackages = builtins.attrValues {
    inherit (pkgs) lenovo-con-mode telegram-desktop;
    inherit (pkgs.unstable) jq;
  };
}
