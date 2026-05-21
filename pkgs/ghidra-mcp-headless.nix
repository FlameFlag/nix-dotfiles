{
  lib,
  ghidra,
  fetchFromGitHub,
  writeShellApplication,
  python313,
  maven,
  jdk21,
  stripJavaArchivesHook,
  curl,
  coreutils,
  bash,
}:
let
  inherit (lib.strings) concatMapStringsSep;

  upstreamRev = "2a57c7cff12e2d6584f2d0e2ba8175bcfb20b43f";
  mvnParameters = lib.escapeShellArgs [ "-Pheadless" ];

  src = fetchFromGitHub {
    owner = "bethington";
    repo = "ghidra-mcp";
    rev = upstreamRev;
    hash = "sha256-OQKsB0vRQjTfdlCUrAWWLQZvgV0TX0mEwjsgjFcWJaA=";
  };

  python = python313.withPackages (ps: [
    ps.mcp
    ps.requests
  ]);
  jarVersion = "5.10.0";
  stateDefault = "$HOME/.local/state/ghidra-mcp-headless";

  requiredGhidraJars = [
    {
      artifactId = "Base";
      path = "Features/Base/lib/Base.jar";
    }
    {
      artifactId = "Decompiler";
      path = "Features/Decompiler/lib/Decompiler.jar";
    }
    {
      artifactId = "Docking";
      path = "Framework/Docking/lib/Docking.jar";
    }
    {
      artifactId = "Generic";
      path = "Framework/Generic/lib/Generic.jar";
    }
    {
      artifactId = "Project";
      path = "Framework/Project/lib/Project.jar";
    }
    {
      artifactId = "SoftwareModeling";
      path = "Framework/SoftwareModeling/lib/SoftwareModeling.jar";
    }
    {
      artifactId = "Utility";
      path = "Framework/Utility/lib/Utility.jar";
    }
    {
      artifactId = "Gui";
      path = "Framework/Gui/lib/Gui.jar";
    }
    {
      artifactId = "FileSystem";
      path = "Framework/FileSystem/lib/FileSystem.jar";
    }
    {
      artifactId = "Help";
      path = "Framework/Help/lib/Help.jar";
    }
    {
      artifactId = "Emulation";
      path = "Framework/Emulation/lib/Emulation.jar";
    }
    {
      artifactId = "Debugger-api";
      path = "Debug/Debugger-api/lib/Debugger-api.jar";
    }
    {
      artifactId = "Framework-TraceModeling";
      path = "Debug/Framework-TraceModeling/lib/Framework-TraceModeling.jar";
    }
    {
      artifactId = "Debugger-rmi-trace";
      path = "Debug/Debugger-rmi-trace/lib/Debugger-rmi-trace.jar";
    }
    {
      artifactId = "DB";
      path = "Framework/DB/lib/DB.jar";
    }
  ];

  installGhidraMavenDeps = repo: ''
    mkdir -p ${repo}
    ${concatMapStringsSep "\n" (jar: ''
      mvn install:install-file \
        -Dmaven.repo.local=${repo} \
        -Dfile=${ghidra}/lib/ghidra/Ghidra/${jar.path} \
        -DgroupId=ghidra \
        -DartifactId=${jar.artifactId} \
        -Dversion=${ghidra.version} \
        -Dpackaging=jar \
        -DgeneratePom=true
    '') requiredGhidraJars}
  '';

  server = maven.buildMavenPackage {
    pname = "ghidra-mcp-headless-server";
    version = jarVersion;

    inherit src;

    mvnJdk = jdk21;
    doCheck = false;
    buildOffline = true;
    strictDeps = true;
    mvnHash = "sha256-9pEPYwPjyPrxn+w8FweKpqsWsTJpw/Op11dvB/glmKI=";
    inherit mvnParameters;
    mvnDepsParameters = mvnParameters;

    nativeBuildInputs = [
      stripJavaArchivesHook
    ];

    postPatch = ''
      substituteInPlace pom.xml \
        --replace-fail "<ghidra.version>12.0.4</ghidra.version>" \
                       "<ghidra.version>${ghidra.version}</ghidra.version>"
    '';

    mvnFetchExtraArgs = {
      preBuild = installGhidraMavenDeps "$out/.m2";
    };

    afterDepsSetup = installGhidraMavenDeps "$mvnDeps/.m2";

    installPhase = ''
      runHook preInstall

      install -Dm644 target/GhidraMCP-${jarVersion}.jar \
        $out/share/java/GhidraMCP-${jarVersion}.jar

      runHook postInstall
    '';
  };
in
rec {
  inherit ghidra src server;

  httpd = writeShellApplication {
    name = "ghidra-mcp-httpd";
    runtimeInputs = [
      bash
      coreutils
      curl
      jdk21
    ];
    text = ''
      set -euo pipefail

      export GHIDRA_HOME="''${GHIDRA_HOME:-${ghidra}/lib/ghidra}"
      export GHIDRA_MCP_BIND="''${GHIDRA_MCP_BIND:-127.0.0.1}"
      export GHIDRA_MCP_PORT="''${GHIDRA_MCP_PORT:-8089}"
      export GHIDRA_MCP_ALLOW_SCRIPTS="''${GHIDRA_MCP_ALLOW_SCRIPTS:-1}"
      export GHIDRA_MCP_AUTH_TOKEN="''${GHIDRA_MCP_AUTH_TOKEN:-}"
      export JAVA_HOME="''${JAVA_HOME:-${jdk21.home}}"
      export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"
      export GHIDRA_USER="''${GHIDRA_USER:-}"

      home_dir="$GHIDRA_MCP_STATE/home"
      mkdir -p "$home_dir"

      export HOME="$home_dir"

      cp="${server}/share/java/GhidraMCP-${jarVersion}.jar"
      for jar in "$GHIDRA_HOME"/Ghidra/Framework/*/lib/*.jar; do cp="$cp:$jar"; done
      for jar in "$GHIDRA_HOME"/Ghidra/Features/*/lib/*.jar; do cp="$cp:$jar"; done
      for jar in "$GHIDRA_HOME"/Ghidra/Debug/*/lib/*.jar; do cp="$cp:$jar"; done
      for jar in "$GHIDRA_HOME"/Ghidra/Processors/*/lib/*.jar; do cp="$cp:$jar"; done

      java_opts=()
      if [ -n "''${JAVA_OPTS:-}" ]; then
        # Intended for simple JVM flags such as "-Xmx4g -XX:+UseG1GC".
        read -r -a java_opts <<< "$JAVA_OPTS"
      fi

      if [ -n "$GHIDRA_USER" ]; then
        java_opts+=("-Duser.name=$GHIDRA_USER")
      fi

      server_args=(--bind "$GHIDRA_MCP_BIND" --port "$GHIDRA_MCP_PORT")
      if [ -n "''${PROGRAM_FILE:-}" ]; then
        server_args+=(--file "$PROGRAM_FILE")
      fi
      if [ -n "''${PROJECT_PATH:-}" ]; then
        server_args+=(--project "$PROJECT_PATH")
      fi
      if [ -n "''${PROGRAM_NAME:-}" ]; then
        server_args+=(--program "$PROGRAM_NAME")
      fi
      if [ -n "''${GHIDRA_MCP_EXTRA_ARGS:-}" ]; then
        # Escape arguments with whitespace by setting explicit PROGRAM_*
        # variables above; this is for simple upstream flags.
        read -r -a extra_args <<< "$GHIDRA_MCP_EXTRA_ARGS"
        server_args+=("''${extra_args[@]}")
      fi

      exec java "''${java_opts[@]}" \
        -Dghidra.home="$GHIDRA_HOME" \
        -Dapplication.name=GhidraMCP \
        -classpath "$cp" \
        com.xebyte.headless.GhidraMCPHeadlessServer \
        "''${server_args[@]}"
    '';
  };

  bridge = writeShellApplication {
    name = "ghidra-mcp-bridge";
    runtimeInputs = [
      python
      curl
    ];
    text = ''
      set -euo pipefail

      export GHIDRA_MCP_BIND="''${GHIDRA_MCP_BIND:-127.0.0.1}"
      export GHIDRA_MCP_PORT="''${GHIDRA_MCP_PORT:-8089}"
      export GHIDRA_MCP_URL="''${GHIDRA_MCP_URL:-http://$GHIDRA_MCP_BIND:$GHIDRA_MCP_PORT}"
      export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"
      export GHIDRA_MCP_BRIDGE_HOST="''${GHIDRA_MCP_BRIDGE_HOST:-127.0.0.1}"
      export GHIDRA_MCP_BRIDGE_PORT="''${GHIDRA_MCP_BRIDGE_PORT:-8090}"
      export GHIDRA_MCP_BRIDGE_TRANSPORT="''${GHIDRA_MCP_BRIDGE_TRANSPORT:-streamable-http}"

      ready=0
      for _ in $(seq 1 1800); do
        if curl -fsS "$GHIDRA_MCP_URL/check_connection" >/dev/null 2>&1; then
          ready=1
          break
        fi
        sleep 1
      done
      if [ "$ready" != 1 ]; then
        echo "Ghidra MCP HTTP backend did not become healthy at $GHIDRA_MCP_URL" >&2
        exit 75
      fi

      exec python "${src}/bridge_mcp_ghidra.py" \
        --transport "$GHIDRA_MCP_BRIDGE_TRANSPORT" \
        --mcp-host "$GHIDRA_MCP_BRIDGE_HOST" \
        --mcp-port "$GHIDRA_MCP_BRIDGE_PORT" \
        --no-lazy
    '';
  };

  meta = {
    description = "Pinned upstream bethington Ghidra MCP headless HTTP backend and MCP bridge launchers";
    homepage = "https://github.com/bethington/ghidra-mcp";
    license = lib.licenses.asl20;
    platforms = lib.systems.doubles.darwin ++ lib.systems.doubles.linux;
  };
}
