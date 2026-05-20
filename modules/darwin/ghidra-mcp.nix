{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;
  inherit (lib.meta) getExe;
  inherit (lib.strings)
    concatMapStringsSep
    escapeShellArg
    escapeShellArgs
    optionalString
    ;

  cfg = config.services.ghidra-mcp;
  types = lib.types;
  user = config.system.primaryUser;
  packageSet = pkgs.ghidra-mcp-headless;
  stateDir = cfg.stateDir;
  logDir = cfg.logDir;
  envExe = lib.meta.getExe' pkgs.coreutils "env";
  httpdExe = getExe packageSet.httpd;
  bridgeExe = getExe packageSet.bridge;
  keepAlive = {
    Crashed = true;
    SuccessfulExit = false;
  };
  sourceEnvironmentFiles = optionalString (cfg.environmentFiles != [ ]) ''
    set -a
    ${concatMapStringsSep "\n" (file: ". ${escapeShellArg (toString file)}") cfg.environmentFiles}
    set +a
  '';
  envArgs = env: escapeShellArgs (lib.attrsets.mapAttrsToList (name: value: "${name}=${value}") env);
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

    httpHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8089;
    };

    mcpHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    mcpPort = mkOption {
      type = types.port;
      default = 8090;
    };

    stateDir = mkOption {
      type = types.path;
      default = "/Users/${user}/.local/state/ghidra-mcp-headless";
    };

    logDir = mkOption {
      type = types.path;
      default = "/Users/${user}/Library/Logs/ghidra-mcp";
      description = "Directory where the Ghidra MCP launchd services write logs.";
    };

    allowScripts = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Ghidra MCP script endpoints in the local headless backend.";
    };

    environmentFiles = mkOption {
      type = types.listOf types.path;
      default = [ ];
      example = [ "/run/keys/ghidra-mcp.env" ];
      description = ''
        Environment files to source before starting the Ghidra MCP launchd
        services. This is useful for values such as GHIDRA_MCP_AUTH_TOKEN
        without putting secrets into the Nix store.
      '';
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
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
        exec ${envExe} ${envArgs httpEnvironment} ${escapeShellArg httpdExe}
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
        exec ${envExe} ${envArgs bridgeEnvironment} ${escapeShellArg bridgeExe}
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
