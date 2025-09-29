_: _: super: {
  /**
    # Type: String -> String -> String -> String

    # Example
    ```nix
    mkSuper "super" "t" "new_tab"
    # => "super+t=new_tab"
    ```
  */
  mkSuper =
    superKey: k: c:
    "${superKey}+${k}=${c}";

  /**
    # Type: String -> String -> String -> String

    # Example

    ```nix
    mkSuperPerf "super" "r" "reload_config"
    # => "performable:super+r=reload_config"
    ```
  */
  mkSuperPerf =
    superKey: k: c:
    "performable:${superKey}+${k}=${c}";

  /**
    # Type: String -> String -> String -> String

    # Example

    ```nix
    mkSuperShift "super" "t" "new_window"
    # => "super+shift+t=new_window"
    ```
  */
  mkSuperShift =
    superKey: k: c:
    "${superKey}+shift+${k}=${c}";

  /**
    # Type: String -> String -> String -> String -> String

    # Example

    ```nix
    mkSuperShiftNested "super" "w" "h" "split_horizontal"
    # => "super+shift+w>h=split_horizontal"
    ```
  */
  mkSuperShiftNested =
    superKey: p: k: c:
    "${superKey}+shift+${p}>${k}=${c}";
}
