{ pkgs, config, ... }:
_: super:
let
  inherit (super) mkMerge mapAttrs;
  modKey = if config.nixpkgs.hostPlatform.isDarwin then "Super" else "Ctrl";

  /**
    # Type: String -> AttrSet -> AttrSet

    # Example

    ```nix
    mkBind "t" { NewTab = {}; }
    # => { "bind "Ctrl t"" = { NewTab = {}; }; }  (assuming modKey is "Ctrl")
    ```
  */
  mkBind = key: action: { "bind \"${modKey} ${key}\"" = action; };

  /**
    # Type: String -> AttrSet -> AttrSet

    # Example

    ```nix
    mkShiftBind "r" { SwitchToMode = "Resize"; }
    # => { "bind "Ctrl Shift r"" = { SwitchToMode = "Resize"; }; }
    ```
  */
  mkShiftBind = key: action: { "bind \"${modKey} Shift ${key}\"" = action; };

  /**
    # Type: String -> AttrSet -> AttrSet

    # Example

    ```nix
    mkSimpleBind "Esc" { SwitchToMode = "Normal"; }
    # => { "bind "Esc"" = { SwitchToMode = "Normal"; }; }
    ```
  */
  mkSimpleBind = key: action: { "bind \"${key}\"" = action; };

  /**
    # Type: (String -> AttrSet -> AttrSet) -> String -> AttrSet -> AttrSet

    # Example

    ```nix
    let
      # Create a new binder that always returns to normal mode
      mySimpleAction = mkActionThenNormal mkSimpleBind;
    in
      # Use the new binder
      mySimpleAction "x" { CloseFocus = {}; }

    # => { "bind "x"" = { CloseFocus = {}; SwitchToMode = "Normal"; }; }
    ```
  */
  mkActionThenNormal =
    binder: key: action:
    binder key (action // { SwitchToMode = "Normal"; });

  /**
    # Type: String -> AttrSet -> AttrSet
    # executes an action and then immediately switches back to Normal mode.

    # Example

    ```nix
    mkSimpleAction "f" { ToggleFocusFullscreen = {}; }
    # => { "bind "f"" = { ToggleFocusFullscreen = {}; SwitchToMode = "Normal"; }; }
    ```
  */
  mkSimpleAction = mkActionThenNormal mkSimpleBind;

  /**
    # Type: String -> AttrSet -> AttrSet
    # executes an action and then immediately switches back to Normal mode.

    # Example

    ```nix
    mkCtrlAction "d" { Detach = {}; }
    # => { "bind "Ctrl d"" = { Detach = {}; SwitchToMode = "Normal"; }; }
    ```
  */
  mkCtrlAction = mkActionThenNormal mkBind;

  # A standard set of direction names used by the functions below.
  directions = {
    Up = "Up";
    Down = "Down";
    Left = "Left";
    Right = "Right";
  };

  /**
    # Type: (String -> AttrSet -> AttrSet) -> (String -> AttrSet) -> AttrSet

    # Example

    ```nix
    mkDirectionalActions mkSimpleBind (dir: { MovePane = dir; })
    # => {
    #   "bind "Up"" = { MovePane = "Up"; };
    #   "bind "Down"" = { MovePane = "Down"; };
    #   "bind "Left"" = { MovePane = "Left"; };
    #   "bind "Right"" = { MovePane = "Right"; };
    # }
    ```
  */
  mkDirectionalActions =
    binder: actionFn: mkMerge (builtins.attrValues (mapAttrs (k: v: binder k (actionFn v)) directions));
in
{
  inherit
    directions
    mkBind
    mkShiftBind
    mkSimpleBind
    mkActionThenNormal
    mkSimpleAction
    mkCtrlAction
    mkDirectionalActions
    ;

  /**
    # Type: AttrSet

    # Example Usage
    ```nix
    keybinds.normal = lib.mkMerge [
      mkDirectionalNav
      # ... other binds
    ];
    ```
  */
  mkDirectionalNav = mkDirectionalActions mkShiftBind (dir: {
    MoveFocus = dir;
  });

  /**
    # Type: AttrSet

    # Example Usage

    ```nix
    keybinds.pane = lib.mkMerge [
      mkDirectionalNewPane
      # ... other binds
    ];
    ```
  */
  mkDirectionalNewPane = mkDirectionalActions mkSimpleAction (dir: {
    NewPane = dir;
  });

  /**
    # Type: AttrSet

    # Example Usage

    ```nix
    keybinds.resize = lib.mkMerge [
      mkDirectionalResize
      # ... other binds
    ];
    ```
  */
  mkDirectionalResize = mkDirectionalActions mkSimpleAction (dir: {
    Resize = "Increase ${dir}";
  });

  /**
    # Type: String -> String -> AttrSet

    # Example

    ```nix
    mkModeSwitch "s" "Search"
    # => { "bind "Ctrl s"" = { SwitchToMode = "Search"; }; }
    ```
  */
  mkModeSwitch = key: mode: (mkBind key { SwitchToMode = mode; });

  /**
    # Type: String -> AttrSet

    # Example

    ```nix
    mkQuit "q"
    # => { "bind "Ctrl q"" = { Quit = {}; }; }
    ```
  */
  mkQuit = key: (mkBind key { Quit = { }; });
}
