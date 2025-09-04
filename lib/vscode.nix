{
  pkgs,
  inputs,
  config,
  ...
}:
_: super:
let
  inherit (config.nixpkgs.hostPlatform) system;

  resetLicense =
    drv:
    drv.overrideAttrs (prev: {
      meta = (prev.meta or { }) // {
        license = [ ];
      };
    });

  extensionSets = inputs.nix-vscode-extensions.extensions.${system};
in
{
  /**
    # Type: String -> String -> String -> Derivation

    # Example

    ```nix
    (mkExt pkgs.vscode.version "ms-python" "python")
    (mkExt "1.85.1" "rust-lang" "rust-analyzer")
    ```
  */
  mkExt =
    vscodeVersion: publisher: extension:
    let
      compatibleExtensions = extensionSets.forVSCodeVersion vscodeVersion;
      marketplace = compatibleExtensions.vscode-marketplace;
    in
    resetLicense marketplace.${publisher}.${extension};

  /**
    # Type: AttrSet { latest :: AttrSet, release :: AttrSet }

    # Example

    ```nix
    (vscode-marketplace.latest).ms-python.python
    (vscode-marketplace.release).ms-python.python
    ```
  */
  vscode-marketplace = {
    latest = super.mapAttrsRecursive (_: resetLicense) extensionSets.vscode-marketplace;
    release = super.mapAttrsRecursive (_: resetLicense) extensionSets.vscode-marketplace-release;
  };

  /**
    # Type: AttrSet { latest :: AttrSet, release :: AttrSet }

    # Example

    ```nix
    (open-vsx.latest).jnoortheen.nix-ide
    ```
  */
  open-vsx = {
    latest = super.mapAttrsRecursive (_: resetLicense) inputs.nix-vscode-extensions.extensions.open-vsx;
    release = super.mapAttrsRecursive (
      _: resetLicense
    ) inputs.nix-vscode-extensions.extensions.open-vsx-release;
  };
}
