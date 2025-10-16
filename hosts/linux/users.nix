{ config, ... }:
{
  sops.secrets.nyx-password.neededForUsers = true;

  users.mutableUsers = false;

  users.users = {
    nyx = {
      isNormalUser = true;
      extraGroups = [
        "wheel"
        "network"
        "networkmanager"
        "audio"
      ];
      hashedPasswordFile = config.sops.secrets.nyx-password.path;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAc3DwiG6OJVICR7FQQE+I9R2447GFLrIRyF9+xP6aM5 nyx@lenovo-legion"
      ];
    };
  };
}
