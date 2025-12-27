{
  description = "My NixOS & Darwin System Flake";

  inputs = {
    catppuccin.inputs.nixpkgs.follows = "nixpkgs";
    catppuccin.url = "github:catppuccin/nix";

    flake-compat.url = "github:edolstra/flake-compat";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.url = "github:numtide/flake-utils";

    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-25.11";

    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";

    nix4vscode.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nix4vscode.url = "github:nix-community/nix4vscode";

    nixcord.inputs.flake-compat.follows = "flake-compat";
    nixcord.inputs.flake-parts.follows = "flake-parts";
    nixcord.inputs.nixpkgs.follows = "nixpkgs";
    nixcord.url = "github:KaylorBen/nixcord";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    nur.inputs.flake-parts.follows = "flake-parts";
    nur.inputs.nixpkgs.follows = "nixpkgs";
    nur.url = "github:nix-community/NUR";

    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";

    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";

    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    yazi.url = "github:sxyazi/yazi/2f66561a8251f8788b2b0fd366af90555ecafc86";
    yazi.inputs.nixpkgs.follows = "nixpkgs";
    yazi.inputs.rust-overlay.follows = "rust-overlay";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
      ];

      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];

      perSystem =
        { pkgs, config, ... }:
        {
          treefmt = {
            projectRootFile = "flake.nix";
            programs.nixfmt = {
              enable = true;
              package = pkgs.nixfmt;
            };
          };

          formatter = config.treefmt.build.wrapper;
          checks.treefmt = config.treefmt.build.check;
        };

      flake = {
        nixosModules.default = import ./modules/nixos;
        darwinModules.default = import ./modules/darwin;
        homeModules.default = import ./modules/hm;

        darwinConfigurations = import ./hosts/darwin { inherit inputs; };
        nixosConfigurations = import ./hosts/linux { inherit inputs; };
      };
    };
}
