{
  lib,
  stdenv,
  zig,
}:

stdenv.mkDerivation {
  pname = "lenovo-con-mode";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../.;
    fileset = ../scripts/lenovo-con-mode;
  };

  nativeBuildInputs = [ zig ];

  dontConfigure = true;

  doCheck = true;

  buildPhase = ''
    runHook preBuild

    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global-cache"
    zig build-exe \
      -O ReleaseSafe \
      --cache-dir "$TMPDIR/zig-cache" \
      --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" \
      -femit-bin=lenovo-con-mode \
      scripts/lenovo-con-mode/main.zig

    runHook postBuild
  '';

  checkPhase = ''
    runHook preCheck

    zig test \
      --cache-dir "$TMPDIR/zig-test-cache" \
      --global-cache-dir "$ZIG_GLOBAL_CACHE_DIR" \
      scripts/lenovo-con-mode/main.zig

    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 lenovo-con-mode "$out/bin/lenovo-con-mode"
    runHook postInstall
  '';

  meta = {
    description = "Toggle or set Lenovo Ideapad battery conservation mode";
    mainProgram = "lenovo-con-mode";
    platforms = lib.platforms.linux;
  };
}
