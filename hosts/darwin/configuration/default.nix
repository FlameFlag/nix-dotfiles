{ inputs, ... }:
{
  imports = [
    inputs.sops-nix.darwinModules.sops
    ./http-fixture
    ./platform.nix
    ./services.nix
    ./sops.nix
    ./users.nix
  ];
}
