{ inputs, ... }:
{
  imports = [ inputs.nixcord.darwinModules.nixcord ];

  programs.nixcord.user = "flame";
}
