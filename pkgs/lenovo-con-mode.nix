{
  lib,
  stdenv,
  zig,
}:

stdenv.mkDerivation {
  pname = "lenovo-con-mode";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../scripts/lenovo-con-mode;
    fileset = ../scripts/lenovo-con-mode;
  };

  nativeBuildInputs = [ zig ];

  strictDeps = true;

  doCheck = true;

  meta = {
    description = "Toggle or set Lenovo Ideapad battery conservation mode";
    mainProgram = "lenovo-con-mode";
    platforms = lib.platforms.linux;
  };
}
