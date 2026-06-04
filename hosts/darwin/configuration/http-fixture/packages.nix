{ pkgs, ... }:
{
  environment.systemPackages = [
    pkgs.caddy
    pkgs.http-fixture
  ];
}
