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

    lix-module.inputs.flake-utils.follows = "flake-utils";
    lix-module.inputs.nixpkgs.follows = "nixpkgs";
    lix-module.url = "https://git.lix.systems/lix-project/nixos-module/archive/2.93.3-2.tar.gz";

    lix.inputs.flake-compat.follows = "";
    lix.inputs.nix2container.follows = "";
    lix.inputs.nixpkgs.follows = "nixpkgs";
    lix.inputs.pre-commit-hooks.follows = "";
    lix.url = "https://git.lix.systems/lix-project/lix/archive/2.93.3.tar.gz";

    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.05";

    nix-vscode-extensions.inputs.flake-utils.follows = "flake-utils";
    nix-vscode-extensions.inputs.nixpkgs.follows = "nixpkgs";
    nix-vscode-extensions.url = "github:nix-community/nix-vscode-extensions";

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

    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";

    yazi.url = "github:sxyazi/yazi/e067a705acd1323b3292a83fa09f28973703c41d";
    yazi.inputs.nixpkgs.follows = "nixpkgs";
    yazi.inputs.rust-overlay.follows = "rust-overlay";
  };

  outputs = inputs: {
    darwinConfigurations = import ./hosts/darwin { inherit inputs; };
    nixosConfigurations = import ./hosts/linux { inherit inputs; };
  };
}
