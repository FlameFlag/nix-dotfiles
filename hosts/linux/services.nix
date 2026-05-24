{ pkgs, ... }:
{
  services = {
    xserver.enable = true;
    tailscale.enable = true;
    tailscale.package = pkgs.unstable.tailscale;

    ghidra-mcp = {
      enable = true;
      httpHost = "127.0.0.1";
      httpPort = 8089;
      mcpHost = "127.0.0.1";
      mcpPort = 8090;
      allowScripts = true;
    };

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
