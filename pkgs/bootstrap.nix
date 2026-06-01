{
  curl,
  expat,
  gcc,
  gnumake,
  lib,
  makeWrapper,
  openssl,
  pkg-config,
  rustPlatform,
  zlib,
}:

let
  buildInputs = [
    curl
    expat
    openssl
    zlib
  ];
  includeFlags = lib.strings.concatMapStringsSep " " (pkg: "-I${lib.getDev pkg}/include") buildInputs;
  includePath = lib.strings.concatMapStringsSep ":" (pkg: "${lib.getDev pkg}/include") buildInputs;
  libraryFlags = lib.strings.concatMapStringsSep " " (
    pkg:
    let
      libPath = "${lib.getLib pkg}/lib";
    in
    "-L${libPath} -Wl,-rpath,${libPath}"
  ) buildInputs;
  libraryPath = lib.strings.concatMapStringsSep ":" (pkg: "${lib.getLib pkg}/lib") buildInputs;
in
rustPlatform.buildRustPackage {
  pname = "bootstrap";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.lock
      ../Cargo.toml
      ../bootstrap
      ../crates
      ./http-fixture
      ./gh-hide-comment
      ./lenovo-con-mode
      ./lsp-diagnostic-filter
      ./zellij-theme-tools
    ];
  };
  cargoLock.lockFile = ../Cargo.lock;

  nativeBuildInputs = [ makeWrapper ];

  cargoBuildFlags = [
    "--package"
    "bootstrap-cli"
  ];
  cargoTestFlags = [
    "--package"
    "bootstrap-cli"
  ];

  postInstall = ''
    mkdir -p "$out/share/nix-dotfiles"
    cp -R Cargo.lock Cargo.toml bootstrap crates pkgs "$out/share/nix-dotfiles/"

    wrapProgram "$out/bin/bootstrap" \
      --set BOOTSTRAP_SKIP_SELF_INSTALL 1 \
      --run 'export BOOTSTRAP_REPO_DIR="''${BOOTSTRAP_REPO_DIR:-'"$out/share/nix-dotfiles"'}"' \
      --prefix PATH : "${
        lib.strings.makeBinPath [
          curl.dev
          gcc
          gnumake
          pkg-config
        ]
      }" \
      --prefix CFLAGS " " "${includeFlags}" \
      --prefix LDFLAGS " " "${libraryFlags}" \
      --prefix CPATH : "${includePath}" \
      --prefix LIBRARY_PATH : "${libraryPath}" \
      --prefix LD_LIBRARY_PATH : "${libraryPath}" \
      --prefix NIX_CFLAGS_COMPILE " " "${includeFlags}" \
      --prefix NIX_LDFLAGS " " "${libraryFlags}"
  '';
}
