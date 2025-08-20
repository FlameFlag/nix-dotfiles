{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}:
let
  writeKeybindings = list: (builtins.concatStringsSep "\n" (map (key: ''"${key}": none'') list));

  no_ai_bullshit = [
    "ai_assistant_panel:focus_terminal_input"
    "ai_assistant_panel:reset_context"
    "code_diff_view:edit_requested_edit"
    "code_diff_view:refine_requested_edit"
    "editor_view:inline_code"
    "inline_ai_view:refine"
    "input:set_mode_agent"
    "input:toggle_active_conversation_menu"
    "input:toggle_natural_language_command_search"
    "requested_command:edit"
    "requested_command:refine"
    "suggested_plan:edit"
    "suggested_plan:refine"
    "terminal:accept_prompt_suggestions"
    "terminal:ask_ai_assistant"
    "terminal:open_inline_ai"
    "workspace:toggle_ai_assistant"
  ];

  no_warp_bullshit = [
    "editor_view:toggle_comment"
    "input:toggle_workflows"
    "notebookview:decrease_font_size"
    "notebookview:focus_terminal_input"
    "notebookview:increase_font_size"
    "notebookview:reset_font_size"
    "terminal:toggle_teams_modal"
    "workflowview:save"
    "workspace:check_for_updates"
    "workspace:jump_to_latest_toast"
    "workspace:toggle_command_palette"
    "workspace:toggle_files_palette"
    "workspace:toggle_launch_config_palette"
    "workspace:toggle_navigation_palette"
    "workspace:toggle_warp_drive"
  ];

  keybindgs = ''
    ---
    ${writeKeybindings no_ai_bullshit}
    ${writeKeybindings no_warp_bullshit}
  '';

  warp-terminal-catppuccin = pkgs.callPackage ../../../pkgs/warp-terminal-catppuccin.nix {
    inherit (config.catppuccin) accent;
  };

  warpConfigDir =
    if osConfig.nixpkgs.hostPlatform.isDarwin then ".warp" else ".local/share/warp-terminal";
in
{
  options.hm.warp-terminal.enable = lib.mkEnableOption "Warp Terminal";

  config = lib.mkIf config.hm.warp-terminal.enable {
    home.packages = [ pkgs.warp-terminal ];
    home.file."${warpConfigDir}/themes".source =
      "${warp-terminal-catppuccin.outPath}/share/warp/themes";
    home.file."${warpConfigDir}/keybindings.yaml".text = keybindgs;
  };
}
