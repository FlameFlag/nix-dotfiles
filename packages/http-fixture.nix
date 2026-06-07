{ lib, rustPlatform }:

rustPlatform.buildRustPackage {
  pname = "http-fixture";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.lock
      ../Cargo.toml
      ../crates
      ./system-run-mcp
      ./http-fixture
      ./gh-hide-comment
      ./lenovo-con-mode
      ./lsp-diagnostic-filter
      ./zellij-theme-tools
    ];
  };
  cargoLock.lockFile = ../Cargo.lock;

  cargoBuildFlags = [
    "--package"
    "http-fixture"
  ];
  cargoTestFlags = [
    "--package"
    "http-fixture"
  ];

  meta = {
    description = "Small local fixture HTTP server";
    mainProgram = "http-fixture";
  };
}
