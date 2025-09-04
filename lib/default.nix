specialArgs: self: super:
let
  kanata = import ./kanata.nix specialArgs self super;
  yazi = import ./yazi.nix specialArgs self super;
  vscode = import ./vscode.nix specialArgs self super;
  ghostty = import ./ghostty.nix specialArgs self super;
  zellij = import ./zellij.nix specialArgs self super;
in
kanata // yazi // vscode // ghostty // zellij
