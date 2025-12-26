{
  inputs,
  pkgs,
  lib,
  config,
  ...
}:
let
  starshipJJTomlContent = ''
    module_separator = " "
    reset_color      = false

    [bookmarks]
    exclude      = []
    search_depth = 100

    [[module]]
    type   = "Symbol"
    symbol = "󰠬"
    color  = "Blue"

    [[module]]
    type                 = "Bookmarks"
    separator            = " "
    color                = "Magenta"
    behind_symbol        = "⇣"
    ahead_symbol         = "⇡"
    surround_with_quotes = false

    [[module]]
    type                 = "Commit"
    max_length           = 16
    empty_text           = "(no des)"
    surround_with_quotes = false

    [[module]]
    type      = "State"
    separator = " "

    [module.conflict]
    disabled = false
    text     = "(CONFLICT)"
    color    = "Red"

    [module.divergent]
    disabled = false
    text     = "(DIVERGENT)"
    color    = "Cyan"

    [module.empty]
    disabled = false
    text     = "(EMPTY)"
    color    = "Yellow"

    [module.immutable]
    disabled = false
    text     = "(IMMUTABLE)"
    color    = "Yellow"

    [module.hidden]
    disabled = false
    text     = "(HIDDEN)"
    color    = "Yellow"

    [[module]]
    type     = "Metrics"
    template = "[{changed} {added}{removed}]"
    color    = "Magenta"

    [module.changed_files]
    prefix = ""
    suffix = ""
    color  = "Cyan"

    [module.added_lines]
    prefix = "+"
    suffix = ""
    color  = "Green"

    [module.removed_lines]
    prefix = "-"
    suffix = ""
    color  = "Red"
  '';
in
{
  options.hm.starship.enable = lib.mkEnableOption "Starship";

  config = lib.mkIf config.hm.starship.enable {
    home.file.".config/starship-jj/starship-jj.toml" = {
      source = pkgs.writeText "starship-jj.toml" starshipJJTomlContent;
    };
    home.packages = builtins.attrValues {
      inherit (inputs.starship-jj.packages.${pkgs.stdenvNoCC.hostPlatform.system}) default;
    };
    programs.nushell.envFile.text = ''
      $env.TRANSIENT_PROMPT_COMMAND = ^starship module character
      $env.TRANSIENT_PROMPT_INDICATOR = ""
      $env.TRANSIENT_PROMPT_INDICATOR_VI_INSERT = ""
      $env.TRANSIENT_PROMPT_INDICATOR_VI_NORMAL = ""
      $env.TRANSIENT_PROMPT_MULTILINE_INDICATOR = ""
      $env.TRANSIENT_PROMPT_COMMAND_RIGHT = ^starship module time
    '';
    programs.starship.enable = true;
    programs.starship.settings = {
      add_newline = true;
      command_timeout =
        let
          secToMs = s: s * 1000;
        in
        secToMs 5;

      format = lib.concatStrings [
        "$shell"
        "$os"
        "$directory"
        "\${custom.jj}"
        "$nix_shell"
        "$line_break"
        "$sudo"
        "$character"
        "$command_timeout"
      ];

      right_format = lib.concatStrings [
        "$cmd_duration"
        "$time"
      ];

      shell = {
        disabled = false;
        style = "cyan bold";
        fish_indicator = "λ";
        powershell_indicator = ">_";
        bash_indicator = "\\$";
        zsh_indicator = "%";
        nu_indicator = ">";
        format = "\\[[$indicator]($style)\\] ";
      };

      os = {
        disabled = false;
        style = "bold blue";
        symbols.Macos = "󰀵 ";
        symbols.NixOS = "󱄅 ";
        symbols.Linux = " ";
      };

      directory = {
        truncate_to_repo = false;
        fish_style_pwd_dir_length = 1;
        truncation_symbol = "../";
        format = "in [$path]($style) ";
      };

      custom.jj = {
        command = "prompt";
        format = "$output";
        ignore_timeout = true;
        shell = [
          "starship-jj"
          "--ignore-working-copy"
          "starship"
        ];
        use_stdin = false;
        when = true;
      };

      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
        vimcmd_symbol = "[V](bold red)";
      };

      sudo = {
        style = "bold red";
        symbol = " ";
        disabled = false;
      };

      time = {
        disabled = false;
        time_format = "%X";
        format = "at [$time]($style) ";
        style = "bold blue";
      };

      nix_shell = {
        disabled = false;
        impure_msg = "[impure shell](bold red)";
        pure_msg = "[pure shell](bold green)";
        unknown_msg = "[unknown shell](bold yellow)";
        style = "bold blue";
        format = "inside \\( $state\\) ";
      };
    };
  };
}
