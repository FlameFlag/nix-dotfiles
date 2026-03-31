{
  pkgs,
  lib,
  config,
  ...
}:
{
  launchd.user.agents = {
    symlink-zsh-config = {
      script = ''
        for file in zprofile zshenv; do
          ln -sfn "/etc/''${file}" "/Users/${config.system.primaryUser}/.''${file}"
        done
      '';
      serviceConfig.RunAtLoad = true;
      serviceConfig.StartInterval = 0;
    };

    zero-capslock-delay.serviceConfig = {
      ProgramArguments = [
        "/usr/bin/hidutil"
        "property"
        "--set"
        "{\"CapsLockDelayOverride\":0}"
      ];
      RunAtLoad = true;
      StartInterval = 0;
    };

    atuin-daemon.serviceConfig = {
      ProgramArguments = [
        (lib.getExe' pkgs.unstable.atuin "atuin")
        "daemon"
        "start"
      ];
      RunAtLoad = true;
      KeepAlive = {
        Crashed = true;
        SuccessfulExit = false;
      };
      ProcessType = "Background";
      StandardOutPath = "/Users/${config.system.primaryUser}/Library/Logs/atuin-daemon.log";
      StandardErrorPath = "/Users/${config.system.primaryUser}/Library/Logs/atuin-daemon.log";
    };
  };
}
