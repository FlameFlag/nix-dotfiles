{ config, ... }:
{
  launchd.user.agents."symlink-zsh-config" = {
    script = ''
      for file in zprofile zshenv zshrc; do
        ln -sfn "/etc/''${file}" "/Users/${config.system.primaryUser}/.''${file}"
      done
    '';
    serviceConfig.RunAtLoad = true;
    serviceConfig.StartInterval = 0;
  };

  launchd.user.agents."zero-capslock-delay".serviceConfig = {
    ProgramArguments = [
      "/usr/bin/hidutil"
      "property"
      "--set"
      "{\"CapsLockDelayOverride\":0}"
    ];
    RunAtLoad = true;
    StartInterval = 0;
  };
}
