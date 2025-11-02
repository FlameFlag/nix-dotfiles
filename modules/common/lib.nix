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
}
