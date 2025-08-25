{
  lib,
  myLib,
  config,
  pkgs,
  pkgsUnstable,
  osConfig,
  ...
}:
let
  inherit (osConfig.nixpkgs.hostPlatform) isDarwin;
  inherit (myLib)
    mkBind
    mkShiftBind
    mkSimpleBind
    mkDirectionalNav
    mkModeSwitch
    mkQuit
    ;

  modKey = if isDarwin then "Super" else "Ctrl";
  copy_command = if isDarwin then "pbcopy" else "wl-copy";

  useHelixKeys = config.programs.helix.enable;

  directions = {
    "Up" = "Up";
    "Down" = "Down";
    "Left" = "Left";
    "Right" = "Right";
  };

  mkDirectionalNewPane = lib.mkMerge (
    lib.mapAttrsToList (
      k: v:
      mkSimpleBind k {
        NewPane = v;
        SwitchToMode = "Normal";
      }
    ) directions
  );

  mkDirectionalResize = lib.mkMerge (
    lib.mapAttrsToList (
      k: v:
      mkSimpleBind k {
        Resize = "Increase ${v}";
        SwitchToMode = "Normal";
      }
    ) directions
  );
in
{
  options.hm.zellij.enable = lib.mkEnableOption "Zellij";

  config = lib.mkIf config.hm.zellij.enable {
    programs.zellij.enable = true;
    programs.zellij.package = pkgsUnstable.zellij;
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
          (mkBind modKey "t" { NewTab = { }; }) # New tab
          (mkBind modKey "k" { Clear = { }; }) # Clear pane text
          (mkShiftBind modKey "Backspace" { CloseFocus = { }; }) # Close pane
          (mkShiftBind modKey "c" { Copy = { }; })

          # Tab switching (1-9)
          (lib.mkMerge (map (n: mkBind modKey (toString n) { GoToTab = n; }) (lib.range 1 9)))

          # Super+Shift+direction
          (mkDirectionalNav modKey)

          (mkModeSwitch modKey "g" "Locked")
          (mkShiftBind modKey "r" { SwitchToMode = "Resize"; }) # Resize mode
          (mkShiftBind modKey "s" { SwitchToMode = "Pane"; }) # Pane mode
          (mkModeSwitch modKey "s" "Search")
          (mkModeSwitch modKey "o" "Session")
          (mkQuit modKey "q")

          (mkShiftBind modKey "t" { SwitchToMode = "Tab"; })
          (mkShiftBind modKey "m" { SwitchToMode = "Move"; })
          (mkModeSwitch modKey "b" "Scroll")
        ];

        # Pane mode (Super+Shift+s > direction)
        pane = lib.mkMerge [
          mkDirectionalNewPane
          (mkSimpleBind "p" { SwitchFocus = { }; })
          (mkSimpleBind "x" {
            CloseFocus = { };
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "f" {
            ToggleFocusFullscreen = { };
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "z" {
            TogglePaneFrames = { };
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "w" {
            ToggleFloatingPanes = { };
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "c" {
            SwitchToMode = "RenamePane";
            PaneNameInput = 0;
          })
          (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
        ];

        tab = lib.mkMerge [
          (mkSimpleBind "h" {
            GoToPreviousTab = { };
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "l" {
            GoToNextTab = { };
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "x" {
            CloseTab = { };
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "r" {
            SwitchToMode = "RenameTab";
            TabNameInput = 0;
          })
          (mkSimpleBind "s" {
            ToggleActiveSyncTab = { };
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "b" {
            BreakPane = { };
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
        ];

        move = lib.mkMerge (
          [
            (mkSimpleBind "Left" {
              MovePane = "Left";
              SwitchToMode = "Normal";
            })
            (mkSimpleBind "Right" {
              MovePane = "Right";
              SwitchToMode = "Normal";
            })
            (mkSimpleBind "Down" {
              MovePane = "Down";
              SwitchToMode = "Normal";
            })
            (mkSimpleBind "Up" {
              MovePane = "Up";
              SwitchToMode = "Normal";
            })
            (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
          ]
          ++ lib.optionals useHelixKeys [
            (mkSimpleBind "h" {
              MovePane = "Left";
              SwitchToMode = "Normal";
            })
            (mkSimpleBind "l" {
              MovePane = "Right";
              SwitchToMode = "Normal";
            })
            (mkSimpleBind "j" {
              MovePane = "Down";
              SwitchToMode = "Normal";
            })
            (mkSimpleBind "k" {
              MovePane = "Up";
              SwitchToMode = "Normal";
            })
            (mkSimpleBind "n" {
              MovePane = { };
              SwitchToMode = "Normal";
            }) # Move to next tab
            (mkSimpleBind "p" {
              MovePaneBackwards = { };
              SwitchToMode = "Normal";
            }) # Move to prev tab
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

        locked = (mkModeSwitch modKey "g" "Normal");

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
