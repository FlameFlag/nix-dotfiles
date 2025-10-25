{
  inputs,
  pkgsUnstable,
  config,
  ...
}:
{
  imports = [ inputs.sops-nix.darwinModules.sops ];

  system.primaryUser = "flame";

  nixpkgs.hostPlatform.system = "aarch64-darwin";

  users.users.${config.system.primaryUser} = {
    name = "${config.system.primaryUser}";
    home = "/Users/${config.system.primaryUser}";
    shell = pkgsUnstable.zsh;
  };

  services.tailscale.enable = true;
  services.tailscale.package = pkgsUnstable.tailscale;

  sops = {
    age.keyFile = "/Users/${config.system.primaryUser}/Library/Application Support/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/secrets.yaml;
    secrets.github_ssh = { };
    secrets.lenovo_legion_5_15arh05h_ssh = { };
  };
}
