{
  inputs,
  pkgs,
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
    shell = pkgs.unstable.zsh;
  };

  services.tailscale.enable = true;
  services.tailscale.package = pkgs.unstable.tailscale;

  sops = {
    age.keyFile = "/Users/${config.system.primaryUser}/Library/Application Support/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/secrets.yaml;
    validateSopsFiles = false;
    secrets = {
      github_ssh = {
        uid = 0;
        gid = 0;
        group = "wheel";
        owner = "root";
      };
      raycast-openrouter-api-key = {
        mode = "0644";
        group = "wheel";
        owner = "root";
        uid = 0;
        gid = 0;
      };
    };
  };
}
