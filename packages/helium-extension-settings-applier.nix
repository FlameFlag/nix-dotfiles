{
  stdenv,
  lib,
  bun,
  writableTmpDirAsHomeHook,
}:
let
  root = ./helium-extension-settings-applier;
  pname = "helium-extension-settings-applier";
  version = "0.1.0";

  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + /.fallowrc.jsonc)
      (root + /biome.jsonc)
      (root + /bun.lock)
      (root + /package.json)
      (root + /src)
      (root + /tsconfig.json)
    ];
  };

  nodeModulesHash = {
    "aarch64-darwin" = "sha256-RmJ3NUogtASiMY7sjtTBwL0MAY9h1QudD+RFZWALi5Q=";
    "x86_64-linux" = "sha256-tOk3BDzOoRpnQJBiL6q9saN9KGsmD3y7y/t8xBpyQzo=";
  };
  bunOS = if stdenv.hostPlatform.isDarwin then "darwin" else "linux";
  bunCPU =
    {
      "aarch64" = "arm64";
      "x86_64" = "x64";
    }
    .${stdenv.hostPlatform.parsed.cpu.name}
      or (throw "${pname}: unsupported Bun CPU ${stdenv.hostPlatform.parsed.cpu.name}");

  node_modules = stdenv.mkDerivation {
    pname = "${pname}-node_modules";
    inherit version src;

    impureEnvVars = lib.fetchers.proxyImpureEnvVars ++ [
      "GIT_PROXY_COMMAND"
      "SOCKS_SERVER"
    ];

    nativeBuildInputs = [
      bun
      writableTmpDirAsHomeHook
    ];

    dontConfigure = true;
    dontFixup = true;

    buildPhase = ''
      runHook preBuild

      export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
      bun install --no-progress --frozen-lockfile --backend=copyfile --os=${bunOS} --cpu=${bunCPU}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      mkdir -p $out
      cp -R node_modules $out/node_modules

      runHook postInstall
    '';

    outputHash =
      nodeModulesHash.${stdenv.hostPlatform.system}
        or (throw "${pname}: Bun node_modules hash is not packaged for ${stdenv.hostPlatform.system}");
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  nativeBuildInputs = [ bun ];

  buildPhase = ''
    runHook preBuild

    cp -R ${node_modules}/node_modules node_modules
    patchShebangs node_modules
    bun run typecheck

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    app_dir="$out/lib/${pname}"
    install -d "$app_dir" "$out/bin"
    cp -R src node_modules package.json bun.lock "$app_dir/"
    {
      printf '#!%s\n' '${lib.getExe bun}'
      printf 'import "%s/src/apply-helium-extension-settings.ts"\n' "$app_dir"
    } >"$out/bin/apply-helium-extension-settings"
    chmod 0755 "$out/bin/apply-helium-extension-settings"

    runHook postInstall
  '';

  meta.mainProgram = "apply-helium-extension-settings";
}
