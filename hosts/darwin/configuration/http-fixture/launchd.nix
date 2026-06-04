{
  config,
  lib,
  pkgs,
  ...
}:
let
  settings = import ./settings.nix { inherit config lib; };

  daemon = serviceConfig: {
    inherit serviceConfig;
  };

  backgroundService = {
    RunAtLoad = true;
    KeepAlive = settings.keepAliveUnlessStopped;
    ProcessType = "Background";
  };
in
{
  launchd.daemons = {
    http-fixture = daemon (
      backgroundService
      // {
        Label = "org.nixos.http-fixture";
        ProgramArguments = [
          (lib.meta.getExe pkgs.http-fixture)
          "--config"
          settings.configFile
        ];
        UserName = settings.user;
        GroupName = "staff";
        StandardOutPath = settings.fixtureLog;
        StandardErrorPath = settings.fixtureLog;
      }
    );

    http-fixture-proxy = daemon (
      backgroundService
      // {
        Label = "org.nixos.http-fixture-proxy";
        ProgramArguments = [
          (lib.meta.getExe pkgs.caddy)
          "run"
          "--config"
          settings.caddyfile
          "--adapter"
          "caddyfile"
        ];
        UserName = "root";
        GroupName = "wheel";
        StandardOutPath = settings.proxyLog;
        StandardErrorPath = settings.proxyLog;
      }
    );
  };
}
