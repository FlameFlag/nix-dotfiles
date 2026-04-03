# Generic builder for paid fonts.
# Takes a font entry from sources.nix and produces a derivation,
# optionally patching with nerd-font-patcher.
{ pkgs, lib, ... }:

let
  sources = import ./sources.nix;

  repo = builtins.fetchGit {
    url = "git@github.com:FlameFlag/paid-fonts.git";
    rev = sources.rev;
    ref = "main";
  };

  buildFont =
    fontDef:
    let
      ext = fontDef.format;
      fontDir = if ext == "otf" then "opentype" else "truetype";
      fileGlob = if fontDef ? glob then fontDef.glob else "*.${ext}";
    in
    pkgs.stdenvNoCC.mkDerivation {
      inherit (fontDef) pname version;

      src = "${repo}/${fontDef.path}";

      dontUnpack = true;

      nativeBuildInputs = lib.optionals fontDef.patchNerd [ pkgs.nerd-font-patcher ];

      buildPhase = ''
        runHook preBuild
        mkdir -p out
        for f in $src/${fileGlob}; do
          ${
            if fontDef.patchNerd then
              ''${lib.getExe pkgs.nerd-font-patcher} --complete --careful --no-progressbars "$f" --outputdir out''
            else
              ''cp "$f" out/''
          }
        done
        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall
        install -Dm644 out/*.${ext} -t "$out/share/fonts/${fontDir}/${fontDef.pname}"
        runHook postInstall
      '';

      meta = {
        inherit (fontDef) description;
        license = lib.licenses.unfree;
        platforms = lib.platforms.all;
      };
    };
in
{
  inherit sources buildFont;
  packages = lib.mapAttrs (_: buildFont) sources.fonts;
}
