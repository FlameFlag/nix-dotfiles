{
  description = "My NixOS & Darwin System Flake";

  inputs = {
    catppuccin.inputs.nixpkgs.follows = "nixpkgs";
    catppuccin.url = "github:catppuccin/nix/release-25.05";

    flake-compat.url = "github:edolstra/flake-compat";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.url = "github:numtide/flake-utils";

    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    home-manager.url = "github:nix-community/home-manager/release-25.05";

    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";

    nix4vscode.inputs.nixpkgs.follows = "nixpkgs";
    nix4vscode.url = "github:nix-community/nix4vscode";

    nixcord.inputs.flake-compat.follows = "flake-compat";
    nixcord.inputs.flake-parts.follows = "flake-parts";
    nixcord.inputs.nixpkgs.follows = "nixpkgs";
    nixcord.url = "github:KaylorBen/nixcord";

    nixos-hardware.url = "github:NixOS/nixos-hardware";

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable-small.url = "github:NixOS/nixpkgs/nixos-unstable-small";

    nur.inputs.flake-parts.follows = "flake-parts";
    nur.inputs.nixpkgs.follows = "nixpkgs";
    nur.url = "github:nix-community/NUR";

    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";

    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
    sops-nix.url = "github:Mic92/sops-nix";

    starship-jj.inputs.nixpkgs.follows = "nixpkgs";
    starship-jj.inputs.flake-utils.follows = "flake-utils";
    starship-jj.url = "gitlab:lanastara_foss/starship-jj";

    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    yazi.url = "github:sxyazi/yazi/e067a705acd1323b3292a83fa09f28973703c41d";
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
              package = pkgs.nixfmt-rfc-style;
            };
          };

          formatter = config.treefmt.build.wrapper;
          checks.treefmt = config.treefmt.build.check;
        };

      flake = {
        nixosModules = import ./modules/nixos;
        darwinModules = import ./modules/darwin;
        homeModules = import ./modules/hm;

        darwinConfigurations = import ./hosts/darwin { inherit inputs; };
        nixosConfigurations = import ./hosts/linux { inherit inputs; };
      };
    };
}
