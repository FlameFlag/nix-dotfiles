{
  config,
  osConfig,
  myLib,
  ...
}:
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
    (mkExt "jnoortheen" "nix-ide")

    # Markdown & Docs
    (mkExt "davidanson" "vscode-markdownlint")
    (mkExt "redhat" "vscode-xml")
  ];

  programs.vscode.profiles.default.userSettings = {
    # Theme
    "workbench.iconTheme" = "catppuccin-${config.catppuccin.flavor}";

    # Language specific formatters
    "[nix]" = {
      "editor.defaultFormatter" = "jnoortheen.nix-ide";
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
    "bashIde.explainshellEndpoint" = "http://localhost:5134";
    "nix.enableLanguageServer" = true;
    "nix.serverPath" = "nil";
    "nix.formatterPath" = "nixfmt";
    "nix.serverSettings" = {
      nil = {
        formatting = {
          command = [
            "nixfmt"
          ];
        };
      };
      nixd = {
        formatting = {
          command = [ "nixfmt" ];
        };
        options =
          let
            workspaceFolder =
              if osConfig.nixpkgs.hostPlatform.isDarwin then
                "${config.home.homeDirectory}/Developer/nix-dotfiles"
              else
                "/etc/nixos/";
          in
          {
            nixos = {
              expr = "(builtins.getFlake \"${workspaceFolder}\").nixosConfigurations.${config.home.username}.options";
            };
            home-manager = {
              expr = "(builtins.getFlake \"${workspaceFolder}\").homeConfigurations.${config.home.username}.options";
            };
            nix-darwin = {
              expr = "(builtins.getFlake \"${workspaceFolder}\").darwinConfigurations.${config.home.username}.options";
            };
          };
      };
    };

    # RedHat XML
    "redhat.telemetry.enabled" = false;
  };
}
