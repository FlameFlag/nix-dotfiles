{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  version = "0.5.2";
  sources = {
    aarch64-darwin = {
      artifact = "ziglint-aarch64-macos.tar.gz";
      hash = "sha256-7F7Wk4p+iFGdiTtwd6c3O3dRWeTnCNYxSHtZ8FWyM1Y=";
    };
    aarch64-linux = {
      artifact = "ziglint-aarch64-linux.tar.gz";
      hash = "sha256-Dtjzaah/lji/0OETdGrXkiUu2gaoKsa8P1hIeGQhw0A=";
    };
    x86_64-linux = {
      artifact = "ziglint-x86_64-linux.tar.gz";
      hash = "sha256-XqxsF1/0iDCg4Nl4SpY8wvNfLVOkZSEsyVNSXo9d9rs=";
    };
  };
  source = sources.${stdenvNoCC.hostPlatform.system};
in
stdenvNoCC.mkDerivation {
  pname = "ziglint";
  inherit version;

  src = fetchurl {
    url = "https://github.com/rockorager/ziglint/releases/download/v${version}/${source.artifact}";
    inherit (source) hash;
  };

  sourceRoot = ".";
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    install -D -m755 ziglint $out/bin/ziglint

    runHook postInstall
  '';

  meta = {
    description = "Static analysis for Zig";
    homepage = "https://github.com/rockorager/ziglint";
    license = lib.licenses.mit;
    mainProgram = "ziglint";
    platforms = builtins.attrNames sources;
  };
}
