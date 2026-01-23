{
  description = "My NixOS & Darwin System Flake";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-25.11";

    nixcord.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixcord.url = "github:FlameFlag/nixcord";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";

    sops-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];

      perSystem =
        { pkgs, ... }:
        {
          packages = {
            raycast-ai-openrouter-proxy = pkgs.callPackage ./pkgs/raycast-ai-openrouter-proxy { };
            yt-dlp = pkgs.callPackage ./pkgs/yt-dlp.nix { };
            yt-dlp-script = pkgs.callPackage ./pkgs/yt-dlp-script.nix { };
            catppuccin-userstyles = pkgs.callPackage ./pkgs/catppuccin-userstyles.nix { };
          };
        };

      flake = {
        nixosModules.default = import ./modules/nixos;
        darwinModules.default = import ./modules/darwin;

        darwinConfigurations = import ./hosts/darwin { inherit inputs; };
        nixosConfigurations = import ./hosts/linux { inherit inputs; };
      };
    };
}
