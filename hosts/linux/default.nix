{ inputs, ... }:
{
  lenovo-legion = inputs.nixpkgs.lib.nixosSystem {
    specialArgs = { inherit inputs; };
    modules = [
      ./configuration.nix
      inputs.nur.modules.nixos.default
      inputs.nixos-hardware.nixosModules.lenovo-legion-15arh05h
      inputs.self.nixosModules
      {
        nixOS = {
          gnome.enable = true;
          dconf.enable = true;
          nvidia.enable = true;
          amd.enable = true;
        };
      }
    ]
    ++ [
      inputs.catppuccin.nixosModules.catppuccin
      {
        catppuccin = {
          enable = true;
          flavor = "frappe";
          accent = "blue";
        };
      }
    ]
    ++ [
      inputs.sops-nix.nixosModules.sops
      {
        sops = {
          age.keyFile = "/home/nyx/.config/sops/age/keys.txt";
          defaultSopsFile = ../../secrets/secrets.yaml;
          secrets.github_ssh = { };
        };
      }
    ];
  };
}
