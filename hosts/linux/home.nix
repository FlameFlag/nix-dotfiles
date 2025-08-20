{ inputs, myLib, ... }:
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = {
      inherit inputs myLib;
      pkgsUnstable = inputs.nixpkgs-unstable.legacyPackages.x86_64-linux;
    };
  };

  home-manager.users.nyx =
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
                vscode.profiles.default.enable = false;
              };
            }
          ];
          hm = [
            ../../modules/hm/browser
            ../../modules/hm/cli
            ../../modules/hm/gui
            ../../modules/hm/terminal
            ../../modules/hm/tui
            {
              hm = {
                atuin.enable = true;
                chromium.enable = true;
                direnv.enable = true;
                fastfetch.enable = true;
                firefox.enable = true;
                fzf.enable = true;
                ghostty.enable = true;
                git.enable = true;
                helix.enable = true;
                mpv.enable = true;
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
        modulesImports ++ catppuccin ++ hm;
    };
}
