{ config, myLib, ... }:
let
  inherit (config.programs.vscode.package) version;
  mkExt = myLib.mkExt version;
in
{
  programs.vscode.profiles.default.extensions = [
    # Utils
    (mkExt "esbenp" "prettier-vscode")
    (mkExt "mkhl" "direnv")
    (mkExt "oderwat" "indent-rainbow")
    (mkExt "visualstudioexptteam" "vscodeintellicode")
    (mkExt "editorconfig" "editorconfig")

    # Languages
    # Bash
    (mkExt "mads-hartmann" "bash-ide-vscode")
    (mkExt "timonwong" "shellcheck")

    # JS & TS
    (mkExt "dbaeumer" "vscode-eslint")
    (mkExt "mgmcdermott" "vscode-language-babel")

    # Nix
    (mkExt "bbenoist" "nix")
    (mkExt "jnoortheen" "nix-ide")
    (mkExt "kamadorueda" "alejandra")

    # Markdown & Docs
    (mkExt "davidanson" "vscode-markdownlint")
    (mkExt "redhat" "vscode-xml")
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
