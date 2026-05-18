{
  pkgs,
  lib,
  config,
  ...
}:
let
  user = config.system.primaryUser;
  keepAliveUnlessStopped = {
    Crashed = true;
    SuccessfulExit = false;
  };
in
{
  launchd.user.agents = {
    symlink-zsh-config = {
      script = ''
        ln -sfn /etc/zprofile /Users/${user}/.zprofile
        if [ "$(readlink /Users/${user}/.zshenv 2>/dev/null)" = /etc/zshenv ]; then
          rm /Users/${user}/.zshenv
        fi
      '';
      serviceConfig.RunAtLoad = true;
      serviceConfig.StartInterval = 0;
    };

    atuin-daemon.serviceConfig = {
      ProgramArguments = [
        (lib.meta.getExe' pkgs.unstable.atuin "atuin")
        "daemon"
        "start"
      ];
      RunAtLoad = true;
      KeepAlive = keepAliveUnlessStopped;
      ProcessType = "Background";
      StandardOutPath = "/Users/${user}/Library/Logs/atuin-daemon.log";
      StandardErrorPath = "/Users/${user}/Library/Logs/atuin-daemon.log";
    };
  };
}
