{
  config,
  pkgs,
  ...
}:
let
  systemRunnerLink = "/Users/${config.system.primaryUser}/.local/bin/system-runner";
  systemRunnerTarget = "/Users/${config.system.primaryUser}/.local/opt/system-run-mcp/latest/bin/system-runner";
in
{
  security.sudo.extraConfig = ''
    Cmnd_Alias SYSTEM_RUNNER = ${systemRunnerLink}, ${systemRunnerTarget}
    ${config.system.primaryUser} ALL=(ALL) NOPASSWD: SYSTEM_RUNNER
  '';

  users.users.${config.system.primaryUser} = {
    name = config.system.primaryUser;
    home = "/Users/${config.system.primaryUser}";
    shell = pkgs.unstable.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAc3DwiG6OJVICR7FQQE+I9R2447GFLrIRyF9+xP6aM5 nyx@lenovo-legion"
    ];
  };
}
