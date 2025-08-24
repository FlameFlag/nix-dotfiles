{
  config,
  osConfig,
  myLib,
  ...
}:
let
  inherit (myLib) mkExt;
  s = osConfig.nixpkgs.hostPlatform.system;
  mkExtForSystem = owner: name: mkExt s owner name;
in
{
  programs.vscode.profiles.default.extensions = [
    # Utils
    (mkExtForSystem "esbenp" "prettier-vscode")
    (mkExtForSystem "mkhl" "direnv")
    (mkExtForSystem "oderwat" "indent-rainbow")
    (mkExtForSystem "visualstudioexptteam" "vscodeintellicode")
    (mkExtForSystem "editorconfig" "editorconfig")

    # Languages
    # Bash
    (mkExtForSystem "mads-hartmann" "bash-ide-vscode")
    (mkExtForSystem "timonwong" "shellcheck")

    # JS & TS
    (mkExtForSystem "dbaeumer" "vscode-eslint")
    (mkExtForSystem "mgmcdermott" "vscode-language-babel")

    # Nix
    (mkExtForSystem "bbenoist" "nix")
    (mkExtForSystem "jnoortheen" "nix-ide")
    (mkExtForSystem "kamadorueda" "alejandra")

    # Markdown & Docs
    (mkExtForSystem "davidanson" "vscode-markdownlint")
    (mkExtForSystem "redhat" "vscode-xml")
  ];

  programs.vscode.profiles.default.userSettings = {
    # Theme
    "workbench.iconTheme" = "catppuccin-${config.catppuccin.flavor}";

    # Language specific formatters
    "[nix]" = {
      "editor.defaultFormatter" = "kamadorueda.alejandra";
      "editor.formatOnPaste" = true;
      "editor.formatOnSave" = true;
      "editor.formatOnType" = true;
    };
    "[javascript]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.formatOnPaste" = true;
      "editor.formatOnSave" = true;
      "editor.formatOnType" = true;
    };
    "[typescript]" = {
      "editor.defaultFormatter" = "esbenp.prettier-vscode";
      "editor.formatOnPaste" = true;
      "editor.formatOnSave" = true;
      "editor.formatOnType" = true;
    };

    # Language server settings
    "nix.enableLanguageServer" = true;
    "nix.serverPath" = "nil";
    "alejandra.program" = "nixfmt";
    "bashIde.explainshellEndpoint" = "http://localhost:5134";

    # RedHat XML
    "redhat.telemetry.enabled" = false;
  };
}
