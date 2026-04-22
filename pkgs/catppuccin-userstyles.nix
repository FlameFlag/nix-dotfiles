{
  pkgs,
  lib,
  flavor ? "frappe",
  accent ? "blue",
  ...
}:

let
  normalizedFlavor = lib.toSentenceCase (
    lib.replaceStrings [ "frappe" ] [ "frappé" ] (lib.toLower flavor)
  );
  normalizedAccent = lib.toSentenceCase accent;
in
assert lib.replaceStrings [ "é" ] [ "e" ] (lib.toLower normalizedFlavor) == lib.toLower flavor;
assert lib.toLower accent == lib.toLower normalizedAccent;

pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "catppuccin-userstyles";
  version = "all-userstyles-export-unstable-2026-02-08";

  src = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "userstyles";
    rev = "d70524f4dd03abe824504734f0b003fd8cb32a8a";
    hash = "sha256-6f0Hke125ToDQZOaq4V9sgNEKtaVaoGtjGn02aWuntQ=";
  };

  buildInputs = [ pkgs.deno ];

  # Set up temporary directories that Deno can write to
  # See: https://docs.deno.com/runtime/getting_started/setup_your_environment/#deno_dir-environment-variable
  # See: https://docs.deno.com/runtime/fundamentals/modules/#deno_dir-environment-variable
  preBuild = ''
    export DENO_DIR="$TMPDIR/deno"
    export XDG_CACHE_HOME="$TMPDIR/cache"
    export HOME="$TMPDIR/home"
    mkdir -p "$DENO_DIR"
    mkdir -p "$XDG_CACHE_HOME"
    mkdir -p "$HOME"
  '';

  buildPhase = ''
    runHook preBuild

    rm -rf ./styles/shinigami-eyes/
    rm -rf ./styles/gmail/

    deno run --allow-read --allow-write --allow-net --allow-env ./scripts/stylus-import/main.ts
    sed -i \
      -e 's/"default":"mocha"/"default":"'"${flavor}"'"/g' \
      -e 's/"default":"mauve"/"default":"'"${accent}"'"/g' \
      -e 's/mocha:Mocha\*"/'${flavor}':'"${normalizedFlavor}"'\*"/g' \
      -e 's/mauve:Mauve\*"/'${accent}':'"${normalizedAccent}"'\*"/g' \
      dist/import.json
      
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/dist"
    cp -r "dist/import.json" $out/dist/
    runHook postInstall
  '';
})
