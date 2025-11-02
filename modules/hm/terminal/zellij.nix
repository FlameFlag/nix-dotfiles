{
  lib,
  myLib,
  config,
  pkgs,
  osConfig,
  ...
}:
let
  inherit (myLib)
    mkBind
    mkShiftBind
    mkSimpleBind
    mkDirectionalNav
    mkModeSwitch
    mkQuit
    mkDirectionalNewPane
    mkDirectionalResize
    mkSimpleAction
    ;

  copy_command = if osConfig.nixpkgs.hostPlatform.isDarwin then "pbcopy" else "wl-copy";

  useHelixKeys = config.programs.helix.enable;
in
{
  options.hm.zellij.enable = lib.mkEnableOption "Zellij";

  config = lib.mkIf config.hm.zellij.enable {
    programs.zellij.enable = true;
    programs.zellij.package = pkgs.unstable.zellij;
    programs.zellij.settings = {
      default_shell = "${lib.getExe pkgs.nushell}";
      inherit copy_command;
      copy_clipboard = "system";
      copy_on_select = false;
      scrollback_editor = "hx";
      mirror_session = true;
      show_startup_tips = false;
      on_force_close = "detach";

      session = lib.mkMerge [
        (mkSimpleBind "d" {
          Detach = { };
          SwitchToMode = "Normal";
        })
        (mkSimpleBind "w" {
          LaunchOrFocusPlugin = "session-manager";
          SwitchToMode = "Normal";
        })
        (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
      ];

      ui.pane_frames = {
        rounded_corners = true;
        hide_session_name = false;
      };

      default_layout = "compact";

      plugins = {
        tab-bar.path = "tab-bar";
        strider.path = "strider";
        compact-bar.path = "compact-bar";
        session-manager.path = "session-manager";
        status-bar.path = "status-bar";
      };

      keybinds = {
        normal = lib.mkMerge [
          (mkBind "t" { NewTab = { }; }) # New tab
          (mkBind "k" { Clear = { }; }) # Clear pane text
          (mkShiftBind "Backspace" { CloseFocus = { }; }) # Close pane
          (mkShiftBind "c" { Copy = { }; })

          # Tab switching (1-9)
          (lib.mkMerge (map (n: mkBind (toString n) { GoToTab = n; }) (lib.range 1 9)))

          # Super+Shift+direction
          (mkDirectionalNav)

          (mkModeSwitch "g" "Locked")
          (mkShiftBind "r" { SwitchToMode = "Resize"; }) # Resize mode
          (mkShiftBind "s" { SwitchToMode = "Pane"; }) # Pane mode
          (mkModeSwitch "s" "Search")
          (mkModeSwitch "o" "Session")
          (mkQuit "q")

          (mkShiftBind "t" { SwitchToMode = "Tab"; })
          (mkShiftBind "m" { SwitchToMode = "Move"; })
          (mkModeSwitch "b" "Scroll")
        ];

        # Pane mode (Super+Shift+s > direction)
        pane = lib.mkMerge [
          mkDirectionalNewPane
          (mkSimpleAction "p" { SwitchFocus = { }; })
          (mkSimpleAction "x" { CloseFocus = { }; })
          (mkSimpleAction "f" { ToggleFocusFullscreen = { }; })
          (mkSimpleAction "z" { TogglePaneFrames = { }; })
          (mkSimpleAction "w" { ToggleFloatingPanes = { }; })
          (mkSimpleBind "c" {
            # This one doesn't switch to Normal, so we use the base helper
            SwitchToMode = "RenamePane";
            PaneNameInput = 0;
          })
          (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
        ];

        tab = lib.mkMerge [
          (mkSimpleAction "h" { GoToPreviousTab = { }; })
          (mkSimpleAction "l" { GoToNextTab = { }; })
          (mkSimpleAction "x" { CloseTab = { }; })
          (mkSimpleAction "s" { ToggleActiveSyncTab = { }; })
          (mkSimpleAction "b" { BreakPane = { }; })
          (mkSimpleBind "r" {
            SwitchToMode = "RenameTab";
            TabNameInput = 0;
          })
          (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
        ];

        move = lib.mkMerge (
          let
            mkMoveActions =
              keyMap: lib.mkMerge (lib.mapAttrsToList (key: dir: mkSimpleAction key { MovePane = dir; }) keyMap);
          in
          [
            (mkMoveActions {
              Left = "Left";
              Right = "Right";
              Down = "Down";
              Up = "Up";
            })
            (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
          ]
          ++ lib.optionals useHelixKeys [
            (mkMoveActions {
              h = "Left";
              l = "Right";
              j = "Down";
              k = "Up";
            })
            (mkSimpleAction "n" { MovePane = { }; }) # Move to next tab
            (mkSimpleAction "p" { MovePaneBackwards = { }; }) # Move to prev tab
          ]
        );

        scroll = lib.mkMerge (
          [
            (mkSimpleBind "Down" { ScrollDown = { }; })
            (mkSimpleBind "Up" { ScrollUp = { }; })
            (mkSimpleBind "PageDown" { PageScrollDown = { }; })
            (mkSimpleBind "PageUp" { PageScrollUp = { }; })
            (mkSimpleBind "e" {
              EditScrollback = { };
              SwitchToMode = "Normal";
            })
            (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
          ]
          ++ lib.optionals useHelixKeys [
            (mkSimpleBind "j" { ScrollDown = { }; })
            (mkSimpleBind "k" { ScrollUp = { }; })
          ]
        );

        # Resize mode (Super+Shift+r > direction)
        resize = lib.mkMerge [
          mkDirectionalResize
          (mkSimpleBind "=" {
            Resize = "Increase";
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "-" {
            Resize = "Decrease";
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
        ];

        renametab = lib.mkMerge [
          (mkSimpleBind "Enter" { SwitchToMode = "Normal"; })
          (mkSimpleBind "Esc" {
            UndoRenameTab = { };
            SwitchToMode = "Tab";
          }) # Go back to Tab mode, not Normal
        ];

        renamepane = lib.mkMerge [
          (mkSimpleBind "Enter" { SwitchToMode = "Normal"; })
          (mkSimpleBind "Esc" {
            UndoRenamePane = { };
            SwitchToMode = "Pane";
          }) # Go back to Pane mode, not Normal
        ];

        locked = (mkModeSwitch "g" "Normal");

        search = lib.mkMerge (
          [
            (mkSimpleBind "/" {
              SwitchToMode = "EnterSearch";
              SearchInput = 0;
            })
            (mkSimpleBind "c" { SearchToggleOption = "CaseSensitivity"; })
            (mkSimpleBind "w" { SearchToggleOption = "WholeWord"; })
            (mkSimpleBind "e" {
              EditScrollback = { };
              SwitchToMode = "Normal";
            })
            (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
          ]
          ++ lib.optionals useHelixKeys [
            (mkSimpleBind "n" { Search = "down"; })
            (mkSimpleBind "N" { Search = "up"; })
          ]
        );
      };
    };
  };
}
