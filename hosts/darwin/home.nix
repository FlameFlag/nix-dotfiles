{
  pkgsUnstable,
  inputs,
  myLib,
  ...
}:
{
  imports = [ inputs.home-manager.darwinModules.home-manager ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs myLib pkgsUnstable; };
  };

  home-manager.users.flame =
    { config, ... }:
    {
      imports =
        let
          core = [ { home.stateVersion = "25.05"; } ];
          catppuccin = [
            inputs.catppuccin.homeModules.catppuccin
            {
              catppuccin = {
                enable = true;
                flavor = "frappe";
                accent = "blue";
              };
            }
            (
              let
                catppuccin-userstyles = pkgsUnstable.callPackage ../../pkgs/catppuccin-userstyles.nix {
                  inherit (config.catppuccin) accent flavor;
                };
              in
              {
                home.file."Documents/catppuccin-userstyles.json".source =
                  "${catppuccin-userstyles.outPath}/dist/import.json";
              }
            )
          ];
          macos-remap-keys = [
            {
              services.macos-remap-keys.enable = true;
              services.macos-remap-keys.keyboard = {
                Capslock = "Escape";
                Escape = "Capslock";
              };
            }
          ];
          myHmModules = [
            ../../modules/hm
            {
              hm = {
                atuin.enable = true;
                direnv.enable = true;
                fastfetch.enable = true;
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
        core ++ catppuccin ++ macos-remap-keys ++ myHmModules;
    };
}
