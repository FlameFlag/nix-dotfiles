{ pkgs, ... }:
{
  services = {
    xserver.enable = true;
    tailscale.enable = true;
    tailscale.package = pkgs.unstable.tailscale;

    atuin = {
      enable = true;
      port = 8888;
      openFirewall = false;
      openRegistration = false;
      host = "127.0.0.1";
      maxHistoryLength = 8192;
      database.createLocally = true;
    };
  };
}
