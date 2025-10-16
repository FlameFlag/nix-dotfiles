{
  inputs,
  lib,
  pkgs,
  config,
  ...
}:
{
  _module.args.myLib =
    let
      libArgs = { inherit inputs pkgs config; };
    in
    lib.extend ((import ../../lib) libArgs);

  _module.args.pkgsUnstable = import inputs.nixpkgs-unstable-small {
    system = "aarch64-darwin";
    inherit (config.nixpkgs) config;
  };
}
