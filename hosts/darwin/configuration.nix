{
  inputs,
  pkgs,
  pkgsUnstable,
  config,
  ...
}:
{
  imports = [ inputs.sops-nix.darwinModules.sops ];

  system.primaryUser = "anon";

  nixpkgs.hostPlatform.system = "aarch64-darwin";

  users.users.anon = {
    name = "anon";
    home = "/Users/anon";
    shell = pkgs.zsh;
  };

  nixOS.lix.enable = true;

  launchd.user.agents."symlink-zsh-config" = {
    script = ''
      for file in zprofile zshenv zshrc; do
        ln -sfn "/etc/''${file}" "/Users/${config.system.primaryUser}/.''${file}"
      done
    '';
    serviceConfig.RunAtLoad = true;
    serviceConfig.StartInterval = 0;
  };

  services.tailscale.enable = true;
  services.tailscale.package = pkgsUnstable.tailscale.overrideAttrs { doCheck = false; };

  sops = {
    age.keyFile = "/Users/${config.system.primaryUser}/Library/Application Support/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/secrets.yaml;
    secrets.github_ssh = { };
    secrets.lenovo_legion_5_15arh05h_ssh = { };
  };
}
