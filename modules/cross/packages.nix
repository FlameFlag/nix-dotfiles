{ lib, pkgs, ... }:
{
  environment.systemPackages = import ../../packages/user-packages.nix { inherit lib pkgs; };
}
