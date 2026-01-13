{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
  modelsJson ? ./models.json,
}:

buildNpmPackage {
  pname = "raycast-ai-openrouter-proxy";
  version = "0.0.2";

  src = fetchFromGitHub {
    owner = "miikkaylisiurunen";
    repo = "raycast-ai-openrouter-proxy";
    rev = "efdcda9204651695824b10a101c67e9a123dc250";
    hash = "sha256-ZHZwrPJdm1iX3GbycDj+Yyuv0GWBqbO18YJpctSuEgU=";
  };

  npmDepsHash = "sha256-M1MPrDdk0ZQXB+TQmKcjuawEKljpPH/d1cC2uDrR9mY=";

  postPatch = ''
    cp ${modelsJson} models.json
  '';

  buildPhase = ''
    runHook preBuild
    npm run build
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/node_modules/raycast-ai-openrouter-proxy"
    cp -r dist "$out/lib/node_modules/raycast-ai-openrouter-proxy"
    cp -r node_modules "$out/lib/node_modules/raycast-ai-openrouter-proxy"
    cp models.json "$out/lib/node_modules/raycast-ai-openrouter-proxy"

    mkdir -p "$out/bin"
    cat > "$out/bin/raycast-ai-openrouter-proxy" <<EOF
    #!/bin/sh
    exec ${lib.getExe' nodejs "node"} $out/lib/node_modules/raycast-ai-openrouter-proxy/dist/index.js
    EOF
    chmod +x "$out/bin/raycast-ai-openrouter-proxy"
    runHook postInstall
  '';
}
