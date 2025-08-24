inputs: _: super:
let
  /**
    # Type: Derivation -> Derivation

    # Example

    ```nix
    resetLicense (mkExt { system = "x86_64-linux"; } "ms-python" "python")
    # Returns the extension with license = []
    ```
  */
  resetLicense =
    drv:
    drv.overrideAttrs (prev: {
      meta = (prev.meta or { }) // {
        license = [ ];
      };
    });
in
{
  /**
    # Type: { system :: String } -> String -> String -> Derivation

    # Example

    ```nix
    mkExt { system = "x86_64-linux"; } "ms-python" "python"
    # Returns the Python extension for Linux x64 with license reset
    ```
  */
  mkExt =
    system: publisher: extension:
    resetLicense
      inputs.nix-vscode-extensions.extensions.${system}.vscode-marketplace.${publisher}.${extension};

  /**
    # Type: { system :: String } -> AttrSet

    # Example

    ```nix
    (vscode-marketplace { system = "x86_64-linux"; }).ms-python.python
    # Access Python extension from marketplace
    ```
  */
  vscode-marketplace =
    system:
    super.lib.mapAttrsRecursive (
      _: resetLicense
    ) inputs.nix-vscode-extensions.extensions.${system}.vscode-marketplace;

  /**
    # Type: { system :: String } -> AttrSet

    # Example

    ```nix
    (vscode-marketplace-release { system = "x86_64-linux"; }).ms-python.python
    ```
  */
  vscode-marketplace-release =
    system:
    super.lib.mapAttrsRecursive (
      _: resetLicense
    ) inputs.nix-vscode-extensions.extensions.${system}.vscode-marketplace-release;

  /**
    # Type: { system :: String } -> AttrSet

    # Example
    ```nix
    (open-vsx { system = "x86_64-linux"; }).jnoortheen.nix-ide
    ```
  */
  open-vsx =
    system:
    super.lib.mapAttrsRecursive (_: resetLicense) inputs.nix-vscode-extensions.extensions.open-vsx;

  /**
    # Type: { system :: String } -> AttrSet

    # Example
    ```nix
    (open-vsx-release { system = "x86_64-linux"; }).jnoortheen.nix-ide
    ```
  */
  open-vsx-release =
    system:
    super.lib.mapAttrsRecursive (
      _: resetLicense
    ) inputs.nix-vscode-extensions.extensions.open-vsx-release;
}
