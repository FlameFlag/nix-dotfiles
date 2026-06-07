{
  description = "My NixOS & Darwin System Flake";

  inputs = {
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";

    dis.inputs.nixpkgs.follows = "nixpkgs-unstable";
    dis.url = "github:FlameFlag/dis";

    eupkgs.inputs.nixpkgs.follows = "nixpkgs-unstable";
    eupkgs.url = "github:euvlok/pkgs";

    nixcord.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixcord.url = "github:FlameFlag/nixcord";

    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable-small";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05-small";

    sops-nix.inputs.nixpkgs.follows = "nixpkgs-unstable";
    sops-nix.url = "github:Mic92/sops-nix";
  };

  outputs =
    inputs:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = inputs.nixpkgs.lib.genAttrs systems;
      commonNixpkgs = import ./modules/cross/nixpkgs.nix { inherit inputs; };
      mkPkgs =
        system:
        import inputs.nixpkgs {
          inherit system;
          config.allowUnfree = true;
          inherit (commonNixpkgs.nixpkgs) overlays;
        };
    in
    {
      formatter = forAllSystems (system: inputs.nixpkgs.legacyPackages.${system}.nixfmt-tree);

      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          inherit (pkgs)
            bootstrap
            chezmoi-support
            dis
            system-run-mcp
            gh-hide-comment
            http-fixture
            kanata
            kanata-with-cmd
            lldb-mcp-launcher
            lsp-diagnostic-filter
            zellij-theme-tools
            ;

          ghidra-mcp-headless-bridge = pkgs.ghidra-mcp-headless.bridge;
          ghidra-mcp-headless-httpd = pkgs.ghidra-mcp-headless.httpd;
          ghidra-mcp-headless-server = pkgs.ghidra-mcp-headless.server;

          default = pkgs.bootstrap;
        }
        // inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          inherit (pkgs) lenovo-con-mode;
        }
      );

      nixosModules.default = import ./modules/nixos;
      darwinModules.default = import ./modules/darwin;

      darwinConfigurations = import ./hosts/darwin { inherit inputs; };
      nixosConfigurations = import ./hosts/linux { inherit inputs; };
    };
}
