{
  pkgs,
  lib,
  ...
}:

let
  src = builtins.fetchGit {
    url = "git@github.com:FlameFlag/paid-fonts.git";
    rev = "24242c863b8080b3d5a1e1488ac0b3b903849b3f";
    ref = "main";
  };
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "tx-02-nerd-font";
  version = "2.002";

  src = "${src}/TX-02";

  dontUnpack = true;

  nativeBuildInputs = [ pkgs.nerd-font-patcher ];

  buildPhase = ''
    runHook preBuild
    mkdir -p patched
    for f in $src/*.ttf; do
      ${lib.getExe pkgs.nerd-font-patcher} --complete --careful --no-progressbars "$f" --outputdir patched
    done
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm644 patched/*.ttf -t `$out/share/fonts/truetype/TX-02-NerdFont`
    runHook postInstall
  '';

  meta = {
    description = "TX-02 font patched with Nerd Font glyphs";
    license = lib.licenses.unfree;
    platforms = lib.platforms.all;
  };
}
