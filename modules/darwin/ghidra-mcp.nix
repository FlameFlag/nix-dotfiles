{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.ghidra-mcp;
  user = config.system.primaryUser;
  packageSet = pkgs.ghidra-mcp-headless;
  stateDir = cfg.stateDir;
  logDir = cfg.logDir;
  keepAlive = {
    Crashed = true;
    SuccessfulExit = false;
  };
  sourceEnvironmentFiles = lib.strings.optionalString (cfg.environmentFiles != [ ]) ''
    set -a
    ${lib.strings.concatMapStringsSep "\n" (
      file: ". ${lib.strings.escapeShellArg (toString file)}"
    ) cfg.environmentFiles}
    set +a
  '';
  envArgs =
    env:
    lib.strings.concatStringsSep " " (
      lib.attrsets.mapAttrsToList (name: value: lib.strings.escapeShellArg "${name}=${value}") env
    );
  httpEnvironment = cfg.extraEnvironment // {
    GHIDRA_MCP_BIND = cfg.httpHost;
    GHIDRA_MCP_PORT = toString cfg.httpPort;
    GHIDRA_MCP_ALLOW_SCRIPTS = if cfg.allowScripts then "1" else "0";
    GHIDRA_MCP_STATE = toString stateDir;
    JAVA_OPTS = "-Xmx4g -XX:+UseG1GC";
  };
  bridgeEnvironment = cfg.extraEnvironment // {
    GHIDRA_MCP_BIND = cfg.httpHost;
    GHIDRA_MCP_PORT = toString cfg.httpPort;
    GHIDRA_MCP_URL = "http://${cfg.httpHost}:${toString cfg.httpPort}";
    GHIDRA_MCP_BRIDGE_HOST = cfg.mcpHost;
    GHIDRA_MCP_BRIDGE_PORT = toString cfg.mcpPort;
    GHIDRA_MCP_BRIDGE_TRANSPORT = "streamable-http";
    GHIDRA_MCP_STATE = toString stateDir;
  };
in
{
  options.services.ghidra-mcp = {
    enable = lib.options.mkEnableOption "Ghidra MCP headless HTTP backend plus streamable HTTP MCP bridge";

    httpHost = lib.options.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };

    httpPort = lib.options.mkOption {
      type = lib.types.port;
      default = 8089;
    };

    mcpHost = lib.options.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };

    mcpPort = lib.options.mkOption {
      type = lib.types.port;
      default = 8090;
    };

    stateDir = lib.options.mkOption {
      type = lib.types.path;
      default = "/Users/${user}/.local/state/ghidra-mcp-headless";
    };

    logDir = lib.options.mkOption {
      type = lib.types.path;
      default = "/Users/${user}/Library/Logs/ghidra-mcp";
      description = "Directory where the Ghidra MCP launchd services write logs.";
    };

    allowScripts = lib.options.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Ghidra MCP script endpoints in the local headless backend.";
    };

    environmentFiles = lib.options.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [ ];
      example = [ "/run/keys/ghidra-mcp.env" ];
      description = ''
        Environment files to source before starting the Ghidra MCP launchd
        services. This is useful for values such as GHIDRA_MCP_AUTH_TOKEN
        without putting secrets into the Nix store.
      '';
    };

    extraEnvironment = lib.options.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables passed to the Ghidra MCP launchd services.";
    };
  };

  config = lib.modules.mkIf cfg.enable {
    environment.systemPackages = [
      packageSet.ghidra
      packageSet.httpd
      packageSet.bridge
    ];

    system.activationScripts.extraActivation.text = lib.modules.mkAfter ''
      install -d -m 0755 -o ${user} -g staff '${stateDir}' '${logDir}'
    '';

    launchd.daemons.ghidra-mcp-httpd = {
      script = ''
        ${sourceEnvironmentFiles}
        exec ${pkgs.coreutils}/bin/env ${envArgs httpEnvironment} ${lib.strings.escapeShellArg (lib.meta.getExe packageSet.httpd)}
      '';
      serviceConfig = {
        Label = "org.nixos.ghidra-mcp-httpd";
        UserName = user;
        GroupName = "staff";
        RunAtLoad = true;
        KeepAlive = keepAlive;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/httpd.log";
        StandardErrorPath = "${logDir}/httpd.log";
        WorkingDirectory = toString stateDir;
      };
    };

    launchd.daemons.ghidra-mcp-bridge = {
      script = ''
        ${sourceEnvironmentFiles}
        exec ${pkgs.coreutils}/bin/env ${envArgs bridgeEnvironment} ${lib.strings.escapeShellArg (lib.meta.getExe packageSet.bridge)}
      '';
      serviceConfig = {
        Label = "org.nixos.ghidra-mcp-bridge";
        UserName = user;
        GroupName = "staff";
        RunAtLoad = true;
        KeepAlive = keepAlive;
        ProcessType = "Background";
        StandardOutPath = "${logDir}/bridge.log";
        StandardErrorPath = "${logDir}/bridge.log";
        WorkingDirectory = toString stateDir;
      };
    };
  };
}
