{ pkgs, ... }:
{
  services.kanata = {
    enable = true;
    package = pkgs.kanata-with-cmd;
    keyboards.main.config = builtins.readFile ../../dotfiles/dot_config/kanata/kanata.kbd;
  };
}
