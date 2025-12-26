{
  pkgs,
  config,
  osConfig,
  ...
}:
{
  programs.vscode.profiles.default.extensions = (
    pkgs.nix4vscode.forVscodeVersion (config.programs.vscode.package.version) [
      # Utils
      "esbenp.prettier-vscode"
      "oderwat.indent-rainbow"
      "editorconfig.editorconfig"

      # Languages
      # Bash
      "mads-hartmann.bash-ide-vscode"
      "timonwong.shellcheck"

      # JS & TS
      "dbaeumer.vscode-eslint"
      "mgmcdermott.vscode-language-babel"

      # Nix
      "jnoortheen.nix-ide"

      # Zig
      "ziglang.vscode-zig"

      # Markdown & Docs
      "davidanson.vscode-markdownlint"
      "redhat.vscode-xml"
    ]
  );

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
    "[zig]" = {
      "editor.formatOnSave" = true;
      "editor.formatOnPaste" = true;
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

    # Zig Language Server
    "zig.path" = "zig";
    "zig.zls.path" = "zls";
    "zig.buildOnSave" = false;
  };
}
