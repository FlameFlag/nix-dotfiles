{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}:
let

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

  writeKeybindings = list: (builtins.concatStringsSep "\n" (map (key: ''"${key}": none'') list));

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

  catppuccinThemeConfig =
    let
      capitalize =
        str:
        lib.strings.toUpper (lib.strings.substring 0 1 str)
        + lib.strings.substring 1 (lib.strings.stringLength str) str;
      darkFlavor = config.catppuccin.flavor;
      lightFlavor = "latte";
    in
    {
      themeJson = ''
        {"light":{"Custom":{"name":"Catppuccin ${capitalize lightFlavor}","path":"${config.home.homeDirectory}/${warpConfigDir}/themes/catppuccin_${lightFlavor}.yml"}},"dark":{"Custom":{"name":"Catppuccin ${capitalize darkFlavor}","path":"${config.home.homeDirectory}/${warpConfigDir}/themes/catppuccin_${darkFlavor}.yml"}}}
      '';
      # The preference key is different on Linux and macOS
      darwinKey = "themesConfig";
      linuxKey = "SelectedSystemThemes";
    };

  settings =
    let
      common = {
        bools = {
          # Disable AI
          IsAnyAIEnabled = false;
          DidShowADELaunchModal = true;
          ShouldAddAgentModeChip = false;
          # Disable Telemetry
          TelemetryEnabled = false;
          CrashReportingEnabled = false;
          TelemetryBannerDismissed = true;
          # Other
          IsSettingsSyncEnabled = false;
        };
        # Nothing for now
        jsons = { };
      };

      darwin = {
        bools = {
          AIAutoDetectionEnabled = false;
          AgentModeOnboardingBlockShown = true;
          AgentModeHomepage = false;
        };
        strings = {
          AgentModeSuggestionsBlockState = "";
        };
      };

      linux = {
        # Nothing for now
        bools = { };
        jsons = { };
      };
    in
    if osConfig.nixpkgs.hostPlatform.isDarwin then
      lib.recursiveUpdate common darwin
    else
      lib.recursiveUpdate common linux;

  darwinCommandGenerator = {
    bool =
      name: value:
      "/usr/bin/defaults write dev.warp.Warp-Stable ${name} -bool ${if value then "true" else "false"}";
    string = name: value: "/usr/bin/defaults write dev.warp.Warp-Stable ${name} -string \"${value}\"";
    json = name: value: "/usr/bin/defaults write dev.warp.Warp-Stable ${name} -string '${value}'";
  };

  linuxCommandGenerator =
    let
      prefsFile = "${config.home.homeDirectory}/.config/warp-terminal/user_preferences.json";
    in
    {
      bool =
        name: value:
        "jq '.prefs.${name} = \"${toString value}\"' ${prefsFile} | tee ${prefsFile} > /dev/null";
      string =
        name: value: "jq '.prefs.${name} = \"${value}\"' ${prefsFile} | tee ${prefsFile} > /dev/null";
      json = name: value: "jq '.prefs.${name} = ${value}' ${prefsFile} | tee ${prefsFile} > /dev/null";
    };
in
{
  options.hm.warp-terminal.enable = lib.mkEnableOption "Warp Terminal";

  config = lib.mkIf config.hm.warp-terminal.enable {
    home.packages = [ pkgs.warp-terminal ];
    home.file."${warpConfigDir}/themes".source =
      "${warp-terminal-catppuccin.outPath}/share/warp/themes";
    home.file."${warpConfigDir}/keybindings.yaml".text = keybindgs;
    home.activation.warpSettings =
      let
        setupScript =
          let
            prefsFile = "${config.home.homeDirectory}/.config/warp-terminal/user_preferences.json";
          in
          lib.optionalString osConfig.nixpkgs.hostPlatform.isLinux ''
            if [ ! -f "${prefsFile}" ]; then
              echo '{"prefs":{}}' > "${prefsFile}"
              chmod 600 "${prefsFile}"
            fi
          '';

        generator =
          if osConfig.nixpkgs.hostPlatform.isDarwin then darwinCommandGenerator else linuxCommandGenerator;

        boolCommands = lib.mapAttrsToList generator.bool settings.bools;
        stringCommands = lib.mapAttrsToList generator.string (settings.strings or { });
        jsonCommands = lib.mapAttrsToList generator.json (settings.jsons or { });

        themeCommand =
          if osConfig.nixpkgs.hostPlatform.isDarwin then
            generator.json catppuccinThemeConfig.darwinKey catppuccinThemeConfig.themeJson
          else
            let
              prefsFile = "${config.home.homeDirectory}/.config/warp-terminal/user_preferences.json";
            in
            "jq --argjson theme_config '${catppuccinThemeConfig.themeJson}' '.prefs.${catppuccinThemeConfig.linuxKey} = \$theme_config' ${prefsFile} | tee ${prefsFile} > /dev/null";
      in
      lib.strings.concatStringsSep "\n" (
        [
          setupScript
        ]
        ++ boolCommands
        ++ stringCommands
        ++ jsonCommands
        ++ (lib.optionals config.catppuccin.enable [ themeCommand ])
      );
  };
}
