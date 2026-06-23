{
  stdenv,
  lib,
  bun,
  go,
  writableTmpDirAsHomeHook,
}:
let
  root = ./logitech-battery;
  extensionUuid = "logitech-battery@flame.local";
  pname = "logitech-battery";
  version = "1.0.0";

  src = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + /biome.jsonc)
      (root + /bun.lock)
      (root + /cmd)
      (root + /gnome/metadata.json)
      (root + /package.json)
      (root + /src)
      (root + /tsconfig.json)
    ];
  };

  nodeModulesHash = {
    "x86_64-linux" = "sha256-tMnZocLu1ZT7tdXS6g32nZWfsdl3iXB1wocCEmMQCoE=";
  };
  bunCPU =
    {
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
      bun install --no-progress --frozen-lockfile --backend=copyfile --os=linux --cpu=${bunCPU}

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
  pname = "gnome-shell-extension-logitech-battery";
  inherit version src;

  nativeBuildInputs = [
    bun
    go
  ];

  buildPhase = ''
    runHook preBuild

    cp -R ${node_modules}/node_modules node_modules
    patchShebangs node_modules
    export GO111MODULE=off
    export GOCACHE=$(mktemp -d)
    mkdir -p dist/bin
    go build -trimpath -ldflags="-s -w" -o dist/bin/logitech-hidpp-battery ./cmd/logitech-hidpp-battery
    go build -trimpath -ldflags="-s -w" -o dist/bin/steelseries-arctis-battery ./cmd/steelseries-arctis-battery
    bun run build:gnome

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    extension_dir="$out/share/gnome-shell/extensions/${extensionUuid}"
    install -d "$out/bin"
    install -d "$extension_dir"
    install -m0755 dist/bin/logitech-hidpp-battery "$out/bin/logitech-hidpp-battery"
    install -m0755 dist/bin/steelseries-arctis-battery "$out/bin/steelseries-arctis-battery"
    install -m0644 gnome/metadata.json "$extension_dir/metadata.json"
    install -m0644 dist/gnome/extension.js "$extension_dir/extension.js"

    runHook postInstall
  '';

  passthru.extensionUuid = extensionUuid;
}
