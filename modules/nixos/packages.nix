{ lib, pkgs, ... }:
let
  inherit (lib.attrsets) attrValues;
in
{
  environment.systemPackages = attrValues {
    # Hardware and platform tools
    inherit (pkgs.unstable)
      ghostty
      pciutils
      smartmontools
      wl-clipboard
      ;
  };
}
