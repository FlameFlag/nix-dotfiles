{ config, ... }:
let
  systemRunnerLink = "/home/nyx/.local/bin/system-runner";
  systemRunnerTarget = "/home/nyx/.local/opt/system-run-mcp/latest/bin/system-runner";
in
{
  sops.secrets.nyx-password.neededForUsers = true;

  users.mutableUsers = false;

  security.sudo.extraRules = [
    {
      users = [ "nyx" ];
      commands = [
        {
          command = systemRunnerLink;
          options = [
            "NOPASSWD"
            "SETENV"
          ];
        }
        {
          command = systemRunnerTarget;
          options = [
            "NOPASSWD"
            "SETENV"
          ];
        }
      ];
    }
  ];

  users.groups.keys = {
    members = [ "nyx" ];
  };

  users.users = {
    nyx = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "network"
        "networkmanager"
        "audio"
        "keys"
      ];
      hashedPasswordFile = config.sops.secrets.nyx-password.path;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAc3DwiG6OJVICR7FQQE+I9R2447GFLrIRyF9+xP6aM5 nyx@lenovo-legion"
      ];
    };
  };
}
