_: _: _: {
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
}
