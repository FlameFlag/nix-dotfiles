{
  description = "My NixOS & Darwin System Flake";

  inputs = {
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";

    dis.inputs.nixpkgs.follows = "nixpkgs-unstable";
    dis.url = "github:FlameFlag/dis";

    eupkgs.inputs.nixpkgs.follows = "nixpkgs-unstable";
    eupkgs.url = "github:euvlok/pkgs";

    nixcord.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixcord.url = "github:FlameFlag/nixcord";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11-small";

    sops-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs = inputs: {
    formatter = {
      aarch64-darwin = inputs.nixpkgs.legacyPackages.aarch64-darwin.nixfmt-tree;
      x86_64-linux = inputs.nixpkgs.legacyPackages.x86_64-linux.nixfmt-tree;
    };

    nixosModules.default = import ./modules/nixos;
    darwinModules.default = import ./modules/darwin;

    darwinConfigurations = import ./hosts/darwin { inherit inputs; };
    nixosConfigurations = import ./hosts/linux { inherit inputs; };
  };
}
