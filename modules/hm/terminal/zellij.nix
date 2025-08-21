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

  modKey = if isDarwin then "Super" else "Alt";

  copy_command = if isDarwin then "pbcopy" else "wl-copy";

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

      ui = {
        pane_frames = {
          rounded_corners = true;
          hide_session_name = false;
        };
      };

      default_layout = "compact";

      plugins = {
        tab-bar = {
          path = "tab-bar";
        };
        strider = {
          path = "strider";
        };
        compact-bar = {
          path = "compact-bar";
        };
        session-manager = {
          path = "session-manager";
        };
        status-bar = {
          path = "status-bar";
        };
      };

      keybinds = {
        normal = lib.mkMerge [
          (mkBind modKey "t" { NewTab = { }; }) # New tab
          (mkBind modKey "k" { Clear = { }; }) # Clear pane text
          (mkShiftBind modKey "Backspace" { CloseFocus = { }; }) # Close pane

          (mkBind modKey "c" { Copy = { }; })

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
          (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
        ];

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

        locked = (mkModeSwitch modKey "g" "Normal");

        search = lib.mkMerge [
          (mkSimpleBind "/" {
            SwitchToMode = "EnterSearch";
            SearchInput = 0;
          })
          (mkSimpleBind "n" { Search = "down"; })
          (mkSimpleBind "N" { Search = "up"; })
          (mkSimpleBind "c" { SearchToggleOption = "CaseSensitivity"; })
          (mkSimpleBind "w" { SearchToggleOption = "WholeWord"; })
          (mkSimpleBind "e" {
            EditScrollback = { };
            SwitchToMode = "Normal";
          })
          (mkSimpleBind "Esc" { SwitchToMode = "Normal"; })
        ];
      };
    };
  };
}
