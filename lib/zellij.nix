_: _: super:
let
  inherit (super) mkMerge mapAttrsToList;
  mkBind = modKey: key: action: { "bind \"${modKey} ${key}\"" = action; };
  mkShiftBind = modKey: key: action: { "bind \"${modKey} Shift ${key}\"" = action; };
  mkSimpleBind = key: action: { "bind \"${key}\"" = action; };

  directions = {
    Up = "Up";
    Down = "Down";
    Left = "Left";
    Right = "Right";
  };
in
{
  # Export directions for use in other modules
  inherit directions;

  # Export binding helper functions
  inherit mkBind mkShiftBind mkSimpleBind;

  mkDirectionalNav =
    modKey: mkMerge (mapAttrsToList (k: v: (mkShiftBind modKey k { MoveFocus = v; })) directions);

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

  mkModeSwitch =
    modKey: key: mode:
    (mkBind modKey key { SwitchToMode = mode; });
  mkQuit = modKey: key: (mkBind modKey key { Quit = { }; });
}
