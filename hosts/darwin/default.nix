{ inputs, ... }:
{
  FlameFlags-Mac-mini = inputs.nix-darwin.lib.darwinSystem {
    specialArgs = { inherit inputs; };
    modules = [
      inputs.self.darwinModules
      ./configuration.nix
      ./home.nix
    ];
  };
}
