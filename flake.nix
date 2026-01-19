{
  description = "My NixOS & Darwin System Flake";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";

    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      perSystem =
        { pkgs, config, ... }:
        {

        };

      flake = {
        nixosModules.default = import ./modules/nixos;
        darwinModules.default = import ./modules/darwin;

        darwinConfigurations = import ./hosts/darwin { inherit inputs; };
        nixosConfigurations = import ./hosts/linux { inherit inputs; };
      };
    };
}
