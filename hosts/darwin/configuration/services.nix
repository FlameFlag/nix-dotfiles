{
  lib,
  pkgs,
  ...
}:
let
  tailscalePackage = pkgs.unstable.tailscale;
  tailscaleExe = lib.meta.getExe tailscalePackage;
in
{
  services = {
    openssh.enable = true;

    tailscale = {
      enable = true;
      package = tailscalePackage;
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

  launchd.daemons.tailscale-ssh = {
    script = ''
      i=0
      while [ "$i" -lt 30 ]; do
        if ${tailscaleExe} set --ssh=true; then
          exit 0
        fi
        i=$((i + 1))
        sleep 2
      done
      exit 1
    '';
    serviceConfig = {
      Label = "com.tailscale.tailscale-ssh";
      RunAtLoad = true;
      KeepAlive = {
        Crashed = true;
        SuccessfulExit = false;
      };
      ThrottleInterval = 30;
      ProcessType = "Background";
      StandardOutPath = "/var/log/tailscale-ssh.log";
      StandardErrorPath = "/var/log/tailscale-ssh.log";
    };
  };
}
