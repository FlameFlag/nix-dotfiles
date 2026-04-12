{
  description = "My NixOS & Darwin System Flake";

  inputs = {
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";

    dis.inputs.nixpkgs.follows = "nixpkgs-unstable";
    dis.url = "github:FlameFlag/dis/v11.2.1";

    eupkgs.inputs.nixpkgs.follows = "nixpkgs-unstable";
    eupkgs.url = "github:euvlok/pkgs";

    niri.inputs.nixpkgs.follows = "nixpkgs";
    niri.url = "github:sodiboo/niri-flake";

    nixcord.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixcord.url = "github:FlameFlag/nixcord";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    quickshell.inputs.nixpkgs.follows = "nixpkgs-unstable";
    quickshell.url = "github:quickshell-mirror/quickshell";

    sops-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs =
    inputs:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      forAllSystems = f: inputs.nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import inputs.nixpkgs { inherit system; };
        in
        {
          gh-hide-comment = pkgs.callPackage ./pkgs/gh-hide-comment.nix { };
          catppuccin-userstyles = pkgs.callPackage ./pkgs/catppuccin-userstyles.nix { };
        }
      );

      nixosModules.default = import ./modules/nixos;
      darwinModules.default = import ./modules/darwin;

      darwinConfigurations = import ./hosts/darwin { inherit inputs; };
      nixosConfigurations = import ./hosts/linux { inherit inputs; };
    };
}
