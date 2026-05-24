{
  lib,
  ghidra,
  stdenv,
  fetchFromGitHub,
  runCommand,
  python313,
  maven,
  jdk21,
  stripJavaArchivesHook,
  curl,
  coreutils,
  makeWrapper,
}:
let
  inherit (lib.strings) concatMapStringsSep concatStringsSep removeSuffix;

  upstreamRev = "5b3bfab00799a64c80b81aac673e964981b94a4f";
  mvnParameters = lib.escapeShellArgs [ "-Pheadless" ];

  src = fetchFromGitHub {
    owner = "bethington";
    repo = "ghidra-mcp";
    rev = upstreamRev;
    hash = "sha256-WitLLnKZ3qTLpZjkIUaPOtJ7+Aki/ycXTWFqiGH/Wyo=";
  };

  python = python313.withPackages (ps: [
    ps.mcp
    ps.requests
  ]);
  jarVersion = "5.12.0";
  stateDefault = "$HOME/.local/state/ghidra-mcp-headless";

  requiredGhidraJarPaths =
    map (name: "Features/${name}/lib/${name}.jar") [
      "Base"
      "Decompiler"
    ]
    ++ map (name: "Framework/${name}/lib/${name}.jar") [
      "DB"
      "Docking"
      "Emulation"
      "FileSystem"
      "Generic"
      "Gui"
      "Help"
      "Project"
      "SoftwareModeling"
      "Utility"
    ]
    ++ map (name: "Debug/${name}/lib/${name}.jar") [
      "Debugger-api"
      "Debugger-rmi-trace"
      "Framework-TraceModeling"
    ];

  ghidraClasspathRoots = [
    "Debug"
    "Features"
    "Framework"
    "Processors"
  ];

  httpdFlags = concatStringsSep " " [
    "\${JAVA_OPTS:-}"
    "\${GHIDRA_USER:+-Duser.name=\"$GHIDRA_USER\"}"
    "-Dghidra.home=\"$GHIDRA_HOME\""
    "-Dapplication.name=GhidraMCP"
    "-classpath @classpath@"
    "com.xebyte.headless.GhidraMCPHeadlessServer"
    "--bind \"$GHIDRA_MCP_BIND\""
    "--port \"$GHIDRA_MCP_PORT\""
    "\${PROGRAM_FILE:+--file \"$PROGRAM_FILE\"}"
    "\${PROJECT_PATH:+--project \"$PROJECT_PATH\"}"
    "\${PROGRAM_NAME:+--program \"$PROGRAM_NAME\"}"
    "\${GHIDRA_MCP_EXTRA_ARGS:-}"
  ];

  bridgeFlags = concatStringsSep " " [
    "${src}/bridge_mcp_ghidra.py"
    "--transport \"$GHIDRA_MCP_BRIDGE_TRANSPORT\""
    "--mcp-host \"$GHIDRA_MCP_BRIDGE_HOST\""
    "--mcp-port \"$GHIDRA_MCP_BRIDGE_PORT\""
    "--no-lazy"
  ];

  installGhidraMavenDeps = repo: ''
    mkdir -p "${repo}"
    ${concatMapStringsSep "\n" (path: ''
      mvn install:install-file \
        -Dmaven.repo.local="${repo}" \
        -Dfile="${ghidra}/lib/ghidra/Ghidra/${path}" \
        -DgroupId="ghidra" \
        -DartifactId="${removeSuffix ".jar" (baseNameOf path)}" \
        -Dversion="${ghidra.version}" \
        -Dpackaging="jar" \
        -DgeneratePom="true"
    '') requiredGhidraJarPaths}
  '';

  server = maven.buildMavenPackage (finalAttrs: {
    pname = "ghidra-mcp-headless-server";
    version = jarVersion;

    inherit src;

    mvnJdk = jdk21;
    doCheck = false;
    buildOffline = true;
    strictDeps = true;
    mvnHash =
      if stdenv.hostPlatform.isDarwin then
        "sha256-25lJJrbKzPexKQklKBwzq6w8uSOK9Sv4tw8/eL6NDSc="
      else
        "sha256-AXdWwQmxqNzw4Eice/WmdytMj3Q0yVu5nInakBAQLm0=";
    inherit mvnParameters;
    mvnDepsParameters = mvnParameters;

    nativeBuildInputs = [
      stripJavaArchivesHook
    ];

    postPatch = ''
      substituteInPlace pom.xml \
        --replace-fail "<ghidra.version>12.1</ghidra.version>" \
                       "<ghidra.version>${ghidra.version}</ghidra.version>"
    '';

    mvnFetchExtraArgs = {
      preBuild = installGhidraMavenDeps "$out/.m2";
    };

    afterDepsSetup = installGhidraMavenDeps "$mvnDeps/.m2";

    installPhase = ''
      runHook preInstall

      install -Dm644 "target/GhidraMCP-${finalAttrs.version}.jar" \
        "$out/share/java/GhidraMCP-${finalAttrs.version}.jar"

      runHook postInstall
    '';
  });

  httpd = runCommand "ghidra-mcp-httpd" { nativeBuildInputs = [ makeWrapper ]; } ''
    classpath="${server}/share/java/GhidraMCP-${jarVersion}.jar"
    for root in ${lib.escapeShellArgs ghidraClasspathRoots}; do
      for jar in "${ghidra}/lib/ghidra/Ghidra/$root"/*/lib/*.jar; do
        classpath="$classpath:$jar"
      done
    done

    flags=${lib.escapeShellArg httpdFlags}
    flags="''${flags//@classpath@/$classpath}"

    mkdir -p "$out/bin"
    makeWrapper "${lib.getExe' jdk21 "java"}" "$out/bin/ghidra-mcp-httpd" \
      --set GHIDRA_HOME "${ghidra}/lib/ghidra" \
      --set-default GHIDRA_MCP_BIND "127.0.0.1" \
      --set-default GHIDRA_MCP_PORT "8089" \
      --set-default GHIDRA_MCP_ALLOW_SCRIPTS "1" \
      --set-default GHIDRA_MCP_AUTH_TOKEN "" \
      --set-default GHIDRA_USER "" \
      --set JAVA_HOME "${jdk21.home}" \
      --run 'export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"' \
      --run '${coreutils}/bin/mkdir -p "$GHIDRA_MCP_STATE/home"' \
      --run 'export HOME="$GHIDRA_MCP_STATE/home"' \
      --add-flags "$flags"
  '';

  bridge = runCommand "ghidra-mcp-bridge" { nativeBuildInputs = [ makeWrapper ]; } ''
    mkdir -p "$out/bin"
    makeWrapper "${lib.getExe' python "python"}" "$out/bin/ghidra-mcp-bridge" \
      --set-default GHIDRA_MCP_BIND "127.0.0.1" \
      --set-default GHIDRA_MCP_PORT "8089" \
      --run 'export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"' \
      --set-default GHIDRA_MCP_BRIDGE_HOST "127.0.0.1" \
      --set-default GHIDRA_MCP_BRIDGE_PORT "8090" \
      --set-default GHIDRA_MCP_BRIDGE_TRANSPORT "streamable-http" \
      --run 'export GHIDRA_MCP_URL="''${GHIDRA_MCP_URL:-http://$GHIDRA_MCP_BIND:$GHIDRA_MCP_PORT}"' \
      --run '${lib.getExe' curl "curl"} -fsS --retry 1800 --retry-delay 1 --retry-connrefused "$GHIDRA_MCP_URL/check_connection" >/dev/null' \
      --add-flags ${lib.escapeShellArg bridgeFlags}
  '';

  meta = {
    description = "Pinned upstream bethington Ghidra MCP headless HTTP backend and MCP bridge launchers";
    homepage = "https://github.com/bethington/ghidra-mcp";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
  };
in
{
  inherit
    bridge
    ghidra
    httpd
    meta
    server
    src
    ;
}
