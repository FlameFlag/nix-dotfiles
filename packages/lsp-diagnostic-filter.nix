{ callPackage }:

callPackage ./go-workspace-package.nix { } {
  pname = "lsp-diagnostic-filter";
  subPackages = [ "cmd/lsp-diagnostic-filter" ];

  meta = {
    description = "Language server wrapper that filters unwanted diagnostics";
    mainProgram = "lsp-diagnostic-filter";
  };
}
