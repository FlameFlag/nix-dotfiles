{ inputs, myLib, ... }:
{
  imports = [ inputs.home-manager.nixosModules.home-manager ];

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs myLib; };
  };

  home-manager.users.nyx =
    { osConfig, ... }:
    {
      imports = [
        inputs.self.nixosModules
        { home.stateVersion = "25.05"; }
      ]
      ++ [
        inputs.catppuccin.homeModules.catppuccin
        {
          catppuccin = {
            inherit (osConfig.catppuccin) enable flavor accent;
            ghostty.enable = false;
            helix.enable = false;
          };
        }
      ]
      ++ [
        inputs.self.homeModules
        {
          hm = {
            atuin.enable = true;
            chromium.enable = true;
            firefox.enable = true;
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
    };
}
