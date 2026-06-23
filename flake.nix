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
      formatter = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        pkgs.writeShellApplication {
          name = "dotfiles-format";
          runtimeInputs = with pkgs; [
            git
            gofumpt
            nixfmt-tree
            shfmt
          ];
          text = ''
            set -euo pipefail

            repo_dir="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
            cd "$repo_dir"

            find . -path ./.git -prune -o -name '*.sh' -type f -exec shfmt -w -i 2 -bn {} +
            find . -path ./.git -prune -o -name '*.go' -type f -exec gofumpt -w {} +
            treefmt "$@"
          '';
        }
      );

      packages = forAllSystems (
        system:
        let
          pkgs = mkPkgs system;
        in
        {
          inherit (pkgs)
            chezmoi-support
            dis
            hyper-window-tiling-gnome
            hyper-window-tiling-kde
            http-fixture
            kanata
            kanata-with-cmd
            lldb-mcp-launcher
            lsp-diagnostic-filter
            nd-tools
            system-run-mcp
            toshy
            zellij-theme-tools
            ;

          default = pkgs.immutable-activate;
        }
        // inputs.nixpkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          portable-linux-profile-without-paid-fonts = pkgs.portable-linux-profile.override {
            includePaidFonts = false;
          };

          inherit (pkgs)
            immutable-activate
            lenovo-con-mode
            linux-toolbox-profile
            logitech-battery-gnome
            macos-pointer
            portable-linux-profile
            sushi-preview
            ;

          immutable-profile = pkgs.portable-linux-profile;
        }
      );

      nixosModules.default = import ./modules/nixos;
      darwinModules.default = import ./modules/darwin;

      darwinConfigurations = import ./hosts/darwin { inherit inputs; };
      nixosConfigurations = import ./hosts/linux { inherit inputs; };
    };
}
