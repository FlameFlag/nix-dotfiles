{ pkgsUnstable, ... }:
{
  services = {
    xserver.enable = true;
    tailscale.enable = true;
    tailscale.package = pkgsUnstable.tailscale;
  };
}
