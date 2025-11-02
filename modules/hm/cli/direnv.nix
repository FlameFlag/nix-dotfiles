{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.hm.direnv.enable = lib.mkEnableOption "Direnv";

  config = lib.mkIf config.hm.direnv.enable {
    programs.direnv = {
      enable = true;
      package = pkgs.unstable.direnv;
      nix-direnv.enable = true;
    };
  };
}
