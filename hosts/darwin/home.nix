{
  pkgs,
  inputs,
  myLib,
  ...
}:
{
  imports = [ inputs.home-manager.darwinModules.home-manager ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs myLib; };
  };

  home-manager.users.flame =
    { config, ... }:
    {
      imports =
        let
          catppuccin = [
            inputs.catppuccin.homeModules.catppuccin
            {
              catppuccin = {
                enable = true;
                flavor = "frappe";
                accent = "blue";
                ghostty.enable = false;
                helix.enable = false;
              };
            }
            (
              let
                catppuccin-userstyles = pkgs.unstable.callPackage ../../pkgs/catppuccin-userstyles.nix {
                  inherit (config.catppuccin) accent flavor;
                };
              in
              {
                home.file."Documents/catppuccin-userstyles.json".source =
                  "${catppuccin-userstyles.outPath}/dist/import.json";
              }
            )
          ];
          myHmModules = [
            inputs.self.homeModules
            {
              hm = {
                atuin.enable = true;
                ghostty.enable = true;
                git.enable = true;
                helix.enable = true;
                nixcord.enable = true;
                nushell.enable = true;
                ssh.enable = true;
                starship.enable = true;
                vscode.enable = true;
                warp-terminal.enable = true;
                yazi.enable = true;
                zed-editor.enable = true;
                zellij.enable = true;
                zoxide.enable = true;
              };
            }
          ];
        in
        [
          {
            home.stateVersion = "25.11";
          }
        ]
        ++ catppuccin
        ++ myHmModules;
    };
}
