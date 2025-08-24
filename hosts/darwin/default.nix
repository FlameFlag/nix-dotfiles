{ inputs, myLib, ... }:
let
  pkgsUnstable = (
    { config, ... }:
    {
      _module.args.pkgsUnstable = import inputs.nixpkgs-unstable-small {
        system = "aarch64-darwin";
        config = config.nixpkgs.config;
      };
    }
  );
in
{
  anons-Mac-mini = inputs.nix-darwin.lib.darwinSystem {
    specialArgs = { inherit inputs myLib; };
    modules = [
      pkgsUnstable
      ../../modules/common
      ./configuration.nix
      ./fonts.nix
      ./home.nix
      ./system.nix

      ../../shared/packages.nix

      { nixOS.lix.enable = true; }
    ];
  };
}
