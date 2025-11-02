{ pkgs, ... }:
{
  services = {
    xserver.enable = true;
    tailscale.enable = true;
    tailscale.package = pkgs.unstable.tailscale;
  };
}
