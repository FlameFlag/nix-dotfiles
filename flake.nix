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
    nixpkgs-zig.url = "github:NixOS/nixpkgs";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    sops-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs =
    inputs:
    let
      inherit (inputs.nixpkgs) lib;

      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = lib.genAttrs systems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
          zigPkgs = import inputs.nixpkgs-zig { inherit system; };
        in
        {
          gh-hide-comment = pkgs.callPackage ./pkgs/gh-hide-comment.nix {
            zig = zigPkgs.zig;
          };
          catppuccin-userstyles = pkgs.callPackage ./pkgs/catppuccin-userstyles.nix { };
        }
        // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          lenovo-con-mode = pkgs.callPackage ./pkgs/lenovo-con-mode.nix {
            zig = zigPkgs.zig;
          };
        }
      );

      nixosModules.default = import ./modules/nixos;
      darwinModules.default = import ./modules/darwin;

      darwinConfigurations = import ./hosts/darwin { inherit inputs; };
      nixosConfigurations = import ./hosts/linux { inherit inputs; };
    };
}
