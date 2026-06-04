{ pkgs, ... }:
{
  services = {
    openssh.enable = true;

    tailscale = {
      enable = true;
      package = pkgs.unstable.tailscale;
    };

    ghidra-mcp = {
      enable = true;
      httpHost = "127.0.0.1";
      httpPort = 8089;
      mcpHost = "127.0.0.1";
      mcpPort = 8090;
      allowScripts = true;
    };
  };
}
