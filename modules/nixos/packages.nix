{ lib, pkgs, ... }:
let
  inherit (lib.attrsets) attrValues;
in
{
  environment.systemPackages = attrValues {
    # Hardware and platform tools
    inherit (pkgs.unstable)
      ghostty
      go
      pciutils
      smartmontools
      wl-clipboard
      ;
  };
}
