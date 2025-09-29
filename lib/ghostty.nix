{ pkgs, ... }:
_: super:
let
  superKey = if pkgs.stdenvNoCC.isDarwin then "super" else "ctrl";
in
{
  /**
    # Type: String -> String -> String -> String

    # Example
    ```nix
    mkSuper "t" "new_tab"
    # => "super+t=new_tab"
    ```
  */
  mkSuper = k: c: "${superKey}+${k}=${c}";

  /**
    # Type: String -> String -> String -> String

    # Example

    ```nix
    mkSuperPerf "r" "reload_config"
    # => "performable:super+r=reload_config"
    ```
  */
  mkSuperPerf = k: c: "performable:${superKey}+${k}=${c}";

  /**
    # Type: String -> String -> String -> String

    # Example

    ```nix
    mkSuperShift "t" "new_window"
    # => "super+shift+t=new_window"
    ```
  */
  mkSuperShift = k: c: "${superKey}+shift+${k}=${c}";

  /**
    # Type: String -> String -> String -> String -> String

    # Example

    ```nix
    mkSuperShiftNested "w" "h" "split_horizontal"
    # => "super+shift+w>h=split_horizontal"
    ```
  */
  mkSuperShiftNested =
    p: k: c:
    "${superKey}+shift+${p}>${k}=${c}";
}
