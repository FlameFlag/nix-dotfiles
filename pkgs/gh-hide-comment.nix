{
  lib,
  stdenv,
  makeWrapper,
  cacert,
  gh,
  zig,
}:

stdenv.mkDerivation {
  pname = "gh-hide-comment";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = ../scripts/gh-hide-comment;
  };

  nativeBuildInputs = [
    makeWrapper
    zig
  ];

  dontConfigure = true;

  buildPhase = ''
    runHook preBuild

    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    zig build-exe \
      -lc \
      -O ReleaseSafe \
      --cache-dir "$TMPDIR/zig-cache" \
      --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" \
      -femit-bin=gh-hide-comment \
      scripts/gh-hide-comment/main.zig

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    install -Dm755 gh-hide-comment "$out/libexec/gh-hide-comment/gh-hide-comment"
    makeWrapper "$out/libexec/gh-hide-comment/gh-hide-comment" "$out/bin/gh-hide-comment" \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --prefix PATH : ${
        lib.makeBinPath [
          gh
        ]
      }

    runHook postInstall
  '';

  meta = {
    description = "Hide GitHub comments via the GraphQL minimizeComment mutation";
    mainProgram = "gh-hide-comment";
  };
}
