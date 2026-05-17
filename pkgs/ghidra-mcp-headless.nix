{
  lib,
  ghidra,
  fetchFromGitHub,
  writeShellApplication,
  python313,
  maven,
  jdk21,
  curl,
  jq,
  rsync,
  coreutils,
  gnugrep,
  gnused,
  gawk,
  bash,
  gnutar,
  gzip,
}:
let
  upstreamRev = "2a57c7cff12e2d6584f2d0e2ba8175bcfb20b43f";

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
  sourceStamp = builtins.concatStringsSep ":" [
    "ghidra-mcp"
    upstreamRev
    jarVersion
    ghidra.version
  ];
  stateDefault = "$HOME/.local/state/ghidra-mcp-headless";
in
rec {
  inherit ghidra src;

  httpd = writeShellApplication {
    name = "ghidra-mcp-httpd";
    runtimeInputs = [
      bash
      coreutils
      curl
      jq
      rsync
      gnutar
      gzip
      gnugrep
      gnused
      gawk
      python
      maven
      jdk21
    ];
    text = ''
      set -euo pipefail

      export GHIDRA_HOME="''${GHIDRA_HOME:-${ghidra}/lib/ghidra}"
      export GHIDRA_MCP_BIND="''${GHIDRA_MCP_BIND:-127.0.0.1}"
      export GHIDRA_MCP_PORT="''${GHIDRA_MCP_PORT:-8089}"
      export GHIDRA_MCP_ALLOW_SCRIPTS="''${GHIDRA_MCP_ALLOW_SCRIPTS:-1}"
      export GHIDRA_MCP_AUTH_TOKEN="''${GHIDRA_MCP_AUTH_TOKEN:-}"
      export JAVA_HOME="''${JAVA_HOME:-${jdk21}}"
      export GHIDRA_MCP_STATE="''${GHIDRA_MCP_STATE:-${stateDefault}}"
      export GHIDRA_USER="''${GHIDRA_USER:-}"

      src_dir="$GHIDRA_MCP_STATE/src"
      home_dir="$GHIDRA_MCP_STATE/home"
      m2="$GHIDRA_MCP_STATE/m2/repository"
      pip_cache="$GHIDRA_MCP_STATE/pip-cache"
      mkdir -p "$src_dir" "$home_dir" "$m2" "$pip_cache"

      if [ ! -f "$src_dir/pom.xml" ] || [ ! -f "$src_dir/.source-stamp" ] || [ "$(cat "$src_dir/.source-stamp")" != "${sourceStamp}" ]; then
        rm -rf "$src_dir"
        mkdir -p "$src_dir"
        rsync -a --chmod=u+rwX "${src}/" "$src_dir/"
        printf '%s\n' "${sourceStamp}" > "$src_dir/.source-stamp"
      fi

      export HOME="$home_dir"
      export MAVEN_OPTS="-Dmaven.repo.local=$m2 ''${MAVEN_OPTS:-}"
      export PIP_CACHE_DIR="$pip_cache"

      if [ ! -f "$src_dir/target/GhidraMCP-${jarVersion}.jar" ]; then
        cd "$src_dir"
        # Do not run upstream ensure-prereqs here: it tries to pip-install into
        # the immutable Nix Python. For the Java headless HTTP server we only
        # need Ghidra jars installed into the service-local Maven repository.
        python -m tools.setup install-ghidra-deps --ghidra-path "$GHIDRA_HOME"
        python -m tools.setup build
      fi

      cp="$src_dir/target/GhidraMCP-${jarVersion}.jar"
      for jar in "$GHIDRA_HOME"/Ghidra/Framework/*/lib/*.jar; do cp="$cp:$jar"; done
      for jar in "$GHIDRA_HOME"/Ghidra/Features/*/lib/*.jar; do cp="$cp:$jar"; done
      for jar in "$GHIDRA_HOME"/Ghidra/Debug/*/lib/*.jar; do cp="$cp:$jar"; done
      for jar in "$GHIDRA_HOME"/Ghidra/Processors/*/lib/*.jar; do cp="$cp:$jar"; done
      for jar in "$src_dir"/target/lib/*.jar; do [ -f "$jar" ] && cp="$cp:$jar"; done

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
