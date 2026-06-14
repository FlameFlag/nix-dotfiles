{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "lsp-diagnostic-filter";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.lock
      ../Cargo.toml
      ../crates
      ./system-run-mcp
      ./http-fixture
      ./lenovo-con-mode
      ./lsp-diagnostic-filter
      ./zellij-theme-tools
    ];
  };
  cargoLock.lockFile = ../Cargo.lock;

  cargoBuildFlags = [
    "--package"
    "lsp-diagnostic-filter"
  ];
  cargoTestFlags = [
    "--package"
    "lsp-diagnostic-filter"
  ];
}
