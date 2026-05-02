{
  lib,
  stdenv,
  makeWrapper,
  bun,
  cacert,
  gh,
}:

let
  pname = "gh-hide-comment";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../bun.lock
      ../package.json
      ../scripts/gh-hide-comment.ts
    ];
  };

  node_modules = stdenv.mkDerivation {
    pname = "${pname}-node_modules";
    inherit version src;

    nativeBuildInputs = [ bun ];

    dontConfigure = true;

    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install \
        --frozen-lockfile \
        --ignore-scripts \
        --no-progress \
        --production

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p "$out"
      cp -R node_modules "$out"

      runHook postInstall
    '';

    dontFixup = true;

    outputHash = "sha256-TSyLkUDwio+GRgZP+ZDaH58ZjLoe/UTsHWYAgIZcdDo=";
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [
    bun
    makeWrapper
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    ln -s ${node_modules}/node_modules node_modules
    bun build \
      --target=bun \
      scripts/gh-hide-comment.ts \
      --outfile gh-hide-comment.js

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 gh-hide-comment.js "$out/libexec/gh-hide-comment/gh-hide-comment.js"
    makeWrapper "${bun}/bin/bun" "$out/bin/gh-hide-comment" \
      --add-flags "run --prefer-offline --no-install $out/libexec/gh-hide-comment/gh-hide-comment.js" \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --prefix PATH : ${lib.makeBinPath [ gh ]}

    runHook postInstall
  '';

  meta = {
    description = "Hide GitHub comments via the GraphQL minimizeComment mutation";
    mainProgram = "gh-hide-comment";
  };
}
