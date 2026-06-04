{ config, lib, ... }:
{
  # Add inputs to legacy (nix2) channels, making legacy nix commands consistent.
  environment.etc = lib.attrsets.mapAttrs' (
    name: value: lib.attrsets.nameValuePair "nix/path/${name}" { source = value.flake; }
  ) config.nix.registry;
}
