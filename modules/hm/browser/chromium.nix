{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}:
let
  inherit (osConfig.nixpkgs.hostPlatform) isLinux;

  chromiumConfig = {
    dictionaries = builtins.attrValues { inherit (pkgs.hunspellDictsChromium) en_US; };
    extensions = [
      { id = "cjpalhdlnbpafiamejdnhcphjbkeiagm"; } # Ublock Origin
      { id = "mnjggcdmjocbbbhaepdhchncahnbgone"; } # Sponsor Block
      { id = "enamippconapkdmgfgjchkhakpfinmaj"; } # Dearrow
      { id = "pobhoodpcipjmedfenaigbeloiidbflp"; } # Minimal Twitter/X Theme
    ]
    ++ lib.optionals config.catppuccin.enable [ { id = "lnjaiaapbakfhlbjenjkhffcdpoompki"; } ];
  };
in
{
  options.hm.chromium.enable = lib.mkEnableOption "Chromium";

  config = lib.mkIf config.hm.chromium.enable {
    assertions = [
      {
        assertion = isLinux;
        message = "Declerative Firefox is only available on Linux";
      }
    ];
    programs.chromium = {
      enable = true;
    }
    // chromiumConfig;
    programs.brave = {
      enable = true;
    }
    // chromiumConfig;
  };
}
