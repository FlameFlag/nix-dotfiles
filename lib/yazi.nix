{ pkgs, config, ... }:
_: _:
let
  inherit (config.nixpkgs.hostPlatform) isDarwin;

  /**
    # Type: String -> String -> String -> AttrSet

    # Example

    ```nix
    genKeyBind "Open in editor" "e" "shell 'nvim \"$1\"' --confirm"
    # => {
    #   desc = "Open in editor";
    #   on = "e";
    #   run = "shell 'nvim \"$1\"' --confirm";
    # }
    ```
  */
  genKeyBind = desc: on: run: { inherit desc on run; };

  mod = key: if isDarwin then "<D-${key}>" else "<C-${key}>";

  /**
    # Type: String -> String -> String -> AttrSet
    # Prepends the platform-specific modifier key (Super/Cmd on macOS, Ctrl
    # elsewhere) to the keybinding

    # Example (assuming `modKey` is "Ctrl")

    ```nix
    genModBind "New Tab" "t" "action 'NewTab'"
    # => {
    #   desc = "New Tab";
    #   on = "Ctrl t";
    #   run = "action 'NewTab'";
    # }
    ```
  */
  genModBind =
    desc: on: run:
    genKeyBind desc [ (mod on) ] run;
in
{
  inherit genKeyBind genModBind;

  genGoBind =
    key: name: path:
    genKeyBind "Go to the ${name} directory" [ "g" key ] "cd ${path}";
}
