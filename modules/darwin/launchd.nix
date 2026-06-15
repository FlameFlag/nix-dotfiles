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

    nd-tools-update.serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-lc"
        "exec /Users/${user}/.local/bin/nd-tools update"
      ];
      RunAtLoad = true;
      StartInterval = 21600;
      ProcessType = "Background";
      EnvironmentVariables.PATH = lib.strings.concatStringsSep ":" [
        "/Users/${user}/.bun/bin"
        "/Users/${user}/.bun/install/global/node_modules/.bin"
        "/Users/${user}/.cache/.bun/bin"
        "/Users/${user}/.local/share/nix-dotfiles/immutable/bin"
        "/Users/${user}/.local/bin"
        "/Users/${user}/.cargo/bin"
        "/run/current-system/sw/bin"
        "/nix/var/nix/profiles/default/bin"
        "/usr/local/bin"
        "/usr/bin"
        "/bin"
        "/usr/sbin"
        "/sbin"
      ];
      StandardOutPath = "/Users/${user}/Library/Logs/nd-tools-update.log";
      StandardErrorPath = "/Users/${user}/Library/Logs/nd-tools-update.log";
    };
  };
}
