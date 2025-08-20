{ pkgs, lib, ... }:
{
  home.packages = builtins.attrValues { inherit (pkgs) nodejs_24; };
  programs.vscode.profiles.default.userSettings = {
    "editor.fontFamily" = "'MonaspiceKr Nerd Font Mono', 'UbuntuMono Nerd Font', monospace";
    "editor.wordWrap" = "on";
    "editor.mouseWheelZoom" = true;
    "editor.guides.bracketPairs" = "active";
    "editor.bracketPairColorization.independentColorPoolPerBracketType" = true;
    "editor.accessibilitySupport" = "off";

    "workbench.editor.showIcons" = true;
    "workbench.colorTheme" = lib.mkForce "Catppuccin Frappé";
    "window.zoomLevel" = 1.5;
    "terminal.integrated.fontFamily" =
      "'MonaspiceKr Nerd Font Mono', 'UbuntuMono Nerd Font', monospace";

    "diffEditor.ignoreTrimWhitespace" = false;

    "security.workspace.trust.enabled" = false;

    "chat.agent.enabled" = false; # Remove AI Bullshit (Copilot)

    # Catppuccin
    ## Make semantic highlighting look good
    "editor.semanticHighlighting.enabled" = true;
    ## Prevent VSCode from modifying the terminal colors
    "terminal.integrated.minimumContrastRatio" = 1;
    ## Make the window's titlebar use the workbench colors
    "window.titleBarStyle" = "custom";
  };
}
