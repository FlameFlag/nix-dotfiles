{
  lib,
  config,
  ...
}:
{
  options.hm.starship.enable = lib.mkEnableOption "Starship";

  config = lib.mkIf config.hm.starship.enable {
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
