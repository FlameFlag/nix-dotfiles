{ inputs, ... }:
{
  imports = [ inputs.nixcord.nixosModules.nixcord ];

  programs.nixcord.user = "nyx";
}
