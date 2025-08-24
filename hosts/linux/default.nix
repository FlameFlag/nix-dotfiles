{ inputs, myLib, ... }:
let
  core = [
    pkgsUnstable
    ./configuration.nix
  ];
  pkgsUnstable = (
    { config, ... }:
    {
      _module.args.pkgsUnstable = import inputs.nixpkgs-unstable-small {
        system = "x86_64-linux";
        config = config.nixpkgs.config;
      };
    }
  );
  myModules = [
    ../../modules/common
    ../../modules/nixos
    {
      nixOS = {
        lix.enable = true;
        gnome.enable = true;
        dconf.enable = true;
        nvidia.enable = true;
        amd.enable = true;
      };
    }
  ];
  catppuccin = [
    inputs.catppuccin.nixosModules.catppuccin
    {
      catppuccin = {
        enable = true;
        flavor = "frappe";
        accent = "blue";
      };
    }
  ];
  sops = [
    inputs.sops-nix.nixosModules.sops
    {
      sops = {
        age.keyFile = "/home/nyx/.config/sops/age/keys.txt";
        defaultSopsFile = ../../secrets/secrets.yaml;
        secrets.github_ssh = { };
        secrets.lenovo_legion_5_15arh05h_ssh = { };
      };
    }
  ];
  modules = [
    inputs.nur.modules.nixos.default
    inputs.nixos-hardware.nixosModules.lenovo-legion-15arh05h
  ];
in
{
  lenovo-legion = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs myLib; };
    modules = core ++ myModules ++ catppuccin ++ sops ++ modules;
  };
}
