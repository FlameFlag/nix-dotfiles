_: {
  programs = {
    steam.enable = false;
    _1password.enable = true;
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "nyx" ];
    };
  };
}
