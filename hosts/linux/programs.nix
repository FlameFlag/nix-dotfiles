{ pkgs, ... }:
{
  programs = {
    chromium.enable = true;
    steam.enable = false;
    _1password.enable = true;
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "nyx" ];
    };
  };
}
