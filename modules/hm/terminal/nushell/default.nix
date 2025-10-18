{
  pkgs,
  pkgsUnstable,
  lib,
  config,
  ...
}:
let
  inherit (pkgs.stdenvNoCC.hostPlatform) isDarwin;
  atuin-completions = pkgs.runCommand "atuin-completions.nu" {
    buildInputs = builtins.attrValues { inherit (pkgsUnstable) atuin; };
  } ''atuin gen-completions -s nushell > "$out"'';
in
{
  options.hm.nushell.enable = lib.mkEnableOption "Nushell";

  config = lib.mkIf config.hm.nushell.enable {
    programs.nushell = {
      enable = true;
      package = pkgsUnstable.nushell;
      shellAliases = {
        cd = "__zoxide_z";
        dc = "__zoxide_z";

        v = "hx";
        vi = "hx";
        vim = "hx";
        h = "hx";

        ll = "ls";
        du = "dust";

        cat = "open";
        open = "^open";

        htop = "btop";
        neofetch = "fastfetch";

        update = "nix flake update --flake (readlink -f /etc/nixos/)";
        check =
          if isDarwin then
            "sudo darwin-rebuild check --flake (readlink -f /etc/nixos/)"
          else
            "nix flake check (readlink -f /etc/nixos/)";
        rebuild =
          if isDarwin then
            "sudo darwin-rebuild switch --flake (readlink -f /etc/nixos/)"
          else
            "nixos-rebuild switch --use-remote-sudo --flake (readlink -f /etc/nixos/)";

        # Video
        m4a = "${lib.getExe pkgs.yt-dlp-script} m4a";
        "m4a-cut" = "${lib.getExe pkgs.yt-dlp-script} m4a-cut";
        mp3 = "${lib.getExe pkgs.yt-dlp-script} mp3";
        "mp3-cut" = "${lib.getExe pkgs.yt-dlp-script} mp3-cut";
        mp4 = "${lib.getExe pkgs.yt-dlp-script} mp4";
        "mp4-cut" = "${lib.getExe pkgs.yt-dlp-script} mp4-cut";
      }
      // lib.optionalAttrs isDarwin { micfix = "sudo killall coreaudiod"; };

      configFile.text =
        let
          conf = builtins.toJSON {
            cursor_shape.vi_insert = "line";
            cursor_shape.vi_normal = "block";
            edit_mode = "vi";
            buffer_editor = "hx";

            highlight_resolved_externals = true;
            rm.always_trash = true;
            show_banner = false;
            use_kitty_protocol = true;
          };
        in
        ''
          $env.EDITOR = "hx";
          $env.VISUAL = "hx";
          $env.config = ${conf};
        '';

      extraConfig =
        let
          customCompletions = pkgs.fetchFromGitHub {
            owner = "nushell";
            repo = "nu_scripts";
            rev = "0b97c5e1444b13db7c263bee646dea1e1ffe4ddb";
            hash = "sha256-tKMLaSNniylbo9f0wdUzUZm059RPqyFQlxMtiTPIkWQ=";
          };
          completionTypes = [
            "bat"
            "curl"
            "git"
            "jj"
            "man"
            "nix"
            "rg"
            "ssh"
            "vscode"
            "zellij"
          ];
          sourceCommands = map (
            t: "source ${customCompletions}/custom-completions/${t}/${t}-completions.nu"
          ) completionTypes;
        in
        ''
          ${builtins.concatStringsSep "\n" sourceCommands}
          ${builtins.readFile ./aliases.nu}
          ${lib.optionalString config.programs.atuin.enable "source ${atuin-completions}"}
        '';
    };
  };
}
