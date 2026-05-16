{ lib, ... }:
{
  options.flame.fonts.paid.enable = lib.options.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Install paid/private fonts from the FlameFlag/paid-fonts repository.
      Disable this on hosts or CI environments that cannot access the private font source.
    '';
  };
}
