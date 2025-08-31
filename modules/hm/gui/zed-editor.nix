{
  pkgsUnstable,
  lib,
  config,
  ...
}:
{
  options.hm.zed-editor.enable = lib.mkEnableOption "Zed Editor";

  config = lib.mkIf config.hm.zed-editor.enable {
    programs.zed-editor.enable = true;
    programs.zed-editor.package = pkgsUnstable.zed-editor;

    programs.zed-editor.extensions = [
      "nix"
      "json5"
      "xml"
      "typos"
      "cspell"
      "biome"
      "unicode"
      "env"
      "csv"
      "toml"
      "yaml"
      "ini"
      "beancount"
      "make"
      "cmake"
      "meson"
      "stylelint"
      "http"
      "cargo-appraiser"
      "crates-lsp"
    ];

    programs.zed-editor.userSettings = {
      auto_update = false; # Obviously we can't use that...
      telemetry = {
        diagnostics = false;
        metrics = false;
      };
      wrap_guides = [
        72
        80
        120
      ];
      helix_mode = true;
    };

    programs.zed-editor.userSettings.languages = {
      "Nix" = {
        language_servers = [ "nil" ];
        formatter = {
          external = {
            command = "nixfmt-classic";
          };
        };
      };
      "YAML" = {
        formatter = "language_server";
      };
      "JSON" = {
        formatter = {
          external = {
            command = "prettier";
            arguments = [
              "--parser"
              "json"
              "--stdin-filepath"
              "{buffer_path}"
            ];
          };
        };
      };
      "HTML" = {
        formatter = {
          external = {
            command = "prettier";
            arguments = [
              "--parser"
              "html"
              "--stdin-filepath"
              "{buffer_path}"
            ];
          };
        };
      };
      "CSS" = {
        formatter = {
          external = {
            command = "prettier";
            arguments = [
              "--parser"
              "css"
              "--stdin-filepath"
              "{buffer_path}"
            ];
          };
        };
      };
      "Bash" = {
        language_servers = [ "bash-language-server" ];
        formatter = {
          external = {
            command = "shfmt";
            arguments = [
              "-i"
              "2"
            ];
          };
        };
      };
      "Rust" = {
        language_servers = [ "rust-analyzer" ];
        formatter = "language_server";
      };
    };
  };
}
