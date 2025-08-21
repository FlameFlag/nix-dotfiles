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
    extraSpecialArgs = {
      inherit inputs myLib;
      pkgsUnstable = inputs.nixpkgs-unstable.legacyPackages.aarch64-darwin;
    };
  };

  home-manager.users.anon =
    { config, ... }:
    {
      imports =
        let
          modulesImports = [ { home.stateVersion = "25.05"; } ];
          catppuccin = [
            inputs.catppuccin.homeModules.catppuccin
            {
              catppuccin = {
                enable = true;
                flavor = "frappe";
                accent = "blue";
              };
            }
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
          homePkgs =
            let
              catppuccin-userstyles = pkgs.callPackage ../../pkgs/catppuccin-userstyles.nix {
                inherit (config.catppuccin) accent flavor;
              };
            in
            [
              {
                home = {
                  file."Documents/catppuccin-userstyles.json".source =
                    "${catppuccin-userstyles.outPath}/dist/import.json";
                };
              }
            ];
          hm = [
            ../../modules/hm/cli
            ../../modules/hm/gui
            ../../modules/hm/terminal
            ../../modules/hm/tui
            {
              hm = {
                atuin.enable = true;
                direnv.enable = true;
                fastfetch.enable = true;
                fzf.enable = true;
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
        modulesImports ++ catppuccin ++ macos-remap-keys ++ homePkgs ++ hm;
    };
}
