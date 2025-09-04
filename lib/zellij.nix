{ pkgs, config, ... }:
_: super:
let
  inherit (super) mkMerge mapAttrsToList;

  modKey = if config.nixpkgs.hostPlatform.isDarwin then "Super" else "Ctrl";

  mkBind = key: action: { "bind \"${modKey} ${key}\"" = action; };
  mkShiftBind = key: action: { "bind \"${modKey} Shift ${key}\"" = action; };
  mkSimpleBind = key: action: { "bind \"${key}\"" = action; };

  directions = {
    Up = "Up";
    Down = "Down";
    Left = "Left";
    Right = "Right";
  };
in
{
  inherit
    directions
    mkBind
    mkShiftBind
    mkSimpleBind
    ;

  mkDirectionalNav = mkMerge (mapAttrsToList (k: v: (mkShiftBind k { MoveFocus = v; })) directions);

  mkDirectionalNewPane = mkMerge (
    mapAttrsToList (
      k: v:
      mkSimpleBind k {
        NewPane = v;
        SwitchToMode = "Normal";
      }
    ) directions
  );

  mkDirectionalResize = mkMerge (
    mapAttrsToList (
      k: v:
      mkSimpleBind k {
        Resize = "Increase ${v}";
        SwitchToMode = "Normal";
      }
    ) directions
  );

  mkModeSwitch = key: mode: (mkBind key { SwitchToMode = mode; });
  mkQuit = key: (mkBind key { Quit = { }; });
}
