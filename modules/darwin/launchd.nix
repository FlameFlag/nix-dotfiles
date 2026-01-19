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
        for file in zprofile zshenv zshrc; do
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

    raycast-ai-openrouter-proxy.serviceConfig = {
      ProgramArguments = [
        "/bin/sh"
        "-c"
        ''
          export API_KEY=$(cat ${config.sops.secrets.raycast-openrouter-api-key.path});
          export PORT=11435;
          export BASE_URL=https://openrouter.ai/api/v1;
          exec ${lib.getExe' pkgs.raycast-ai-openrouter-proxy "raycast-ai-openrouter-proxy"}
        ''
      ];
      RunAtLoad = true;
      KeepAlive = true;
    };

    atuin-daemon.serviceConfig = {
      ProgramArguments = [
        (lib.getExe' pkgs.unstable.atuin "atuin")
        "daemon"
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
