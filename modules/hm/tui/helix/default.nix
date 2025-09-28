{
  lib,
  config,
  ...
}:
{
  imports = [
    ./languages.nix
    ./settings.nix
  ];

  options.hm.helix.enable = lib.mkEnableOption "Helix";

  config = lib.mkIf config.hm.helix.enable {
    programs.helix.enable = true;
    programs.helix.defaultEditor = true;
  };
}
