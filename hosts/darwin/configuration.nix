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
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAc3DwiG6OJVICR7FQQE+I9R2447GFLrIRyF9+xP6aM5 nyx@lenovo-legion"
    ];
  };

  services.openssh.enable = true;

  services.tailscale.enable = true;
  services.tailscale.package = pkgs.unstable.tailscale;

  services.ghidra-mcp = {
    enable = true;
    httpHost = "127.0.0.1";
    httpPort = 8089;
    mcpHost = "127.0.0.1";
    mcpPort = 8090;
    allowScripts = true;
  };

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
