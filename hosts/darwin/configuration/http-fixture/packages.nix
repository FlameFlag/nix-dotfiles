{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.caddy
  ];
}
