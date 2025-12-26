{
  pkgs,
  lib,
  flavor ? "frappe",
  accent ? "mauve",
  ...
}:

let
  capitalizeFirst =
    str:
    let
      first = builtins.substring 0 1 str;
      rest = builtins.substring 1 (builtins.stringLength str) str;
    in
    (lib.strings.toUpper first) + rest;

  normalizedFlavor = capitalizeFirst (
    builtins.replaceStrings [ "frappe" ] [ "frappé" ] (lib.strings.toLower flavor)
  );
  normalizedAccent = capitalizeFirst (lib.strings.toLower accent);
in
assert
  builtins.replaceStrings [ "é" ] [ "e" ] (lib.strings.toLower normalizedFlavor)
  == lib.strings.toLower flavor;
assert lib.strings.toLower accent == lib.strings.toLower normalizedAccent;

pkgs.stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "catppuccin-userstyles";
  version = "all-userstyles-export-unstable-2025-12-20";

  src = pkgs.fetchFromGitHub {
    owner = "catppuccin";
    repo = "userstyles";
    rev = "616b334a16a79d9f91df3fbd58c8df55a1428770";
    hash = "sha256-gdG6lo0JpkBNiWl2+XNviXxhjAUlg0/hlSCJfZfbi7c=";
  };

  buildInputs = builtins.attrValues { inherit (pkgs) deno; };

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
