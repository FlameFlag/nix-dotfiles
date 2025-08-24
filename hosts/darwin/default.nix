{ inputs, myLib, ... }:
{
  anons-Mac-mini = inputs.nix-darwin.lib.darwinSystem {
    specialArgs = { inherit inputs myLib; };
    modules = [
      (
        { config, ... }:
        {
          _module.args.pkgsUnstable = import inputs.nixpkgs-unstable-small {
            system = "aarch64-darwin";
            config = config.nixpkgs.config;
          };
        }
      )
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
