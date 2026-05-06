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
  logDir = "/Users/${user}/Library/Logs/ghidra-mcp";
  keepAlive = {
    Crashed = true;
    SuccessfulExit = false;
  };
in
{
  options.services.ghidra-mcp = {
    enable = lib.mkEnableOption "Ghidra MCP headless HTTP backend plus streamable HTTP MCP bridge";

    httpHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8089;
    };

    mcpHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
    };

    mcpPort = lib.mkOption {
      type = lib.types.port;
      default = 8090;
    };

    stateDir = lib.mkOption {
      type = lib.types.path;
      default = "/Users/${user}/.local/state/ghidra-mcp-headless";
    };

    allowScripts = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Ghidra MCP script endpoints in the local headless backend.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      packageSet.ghidra
      packageSet.httpd
      packageSet.bridge
    ];

    system.activationScripts.extraActivation.text = lib.mkAfter ''
      install -d -m 0755 -o ${user} -g staff '${stateDir}' '${logDir}'
    '';

    launchd.daemons.ghidra-mcp-httpd.serviceConfig = {
      Label = "org.nixos.ghidra-mcp-httpd";
      ProgramArguments = [ (lib.getExe packageSet.httpd) ];
      UserName = user;
      GroupName = "staff";
      RunAtLoad = true;
      KeepAlive = keepAlive;
      ProcessType = "Background";
      EnvironmentVariables = {
        GHIDRA_MCP_BIND = cfg.httpHost;
        GHIDRA_MCP_PORT = toString cfg.httpPort;
        GHIDRA_MCP_ALLOW_SCRIPTS = if cfg.allowScripts then "1" else "0";
        GHIDRA_MCP_STATE = toString stateDir;
        JAVA_OPTS = "-Xmx4g -XX:+UseG1GC";
      };
      StandardOutPath = "${logDir}/httpd.log";
      StandardErrorPath = "${logDir}/httpd.log";
      WorkingDirectory = toString stateDir;
    };

    launchd.daemons.ghidra-mcp-bridge.serviceConfig = {
      Label = "org.nixos.ghidra-mcp-bridge";
      ProgramArguments = [ (lib.getExe packageSet.bridge) ];
      UserName = user;
      GroupName = "staff";
      RunAtLoad = true;
      KeepAlive = keepAlive;
      ProcessType = "Background";
      EnvironmentVariables = {
        GHIDRA_MCP_BIND = cfg.httpHost;
        GHIDRA_MCP_PORT = toString cfg.httpPort;
        GHIDRA_MCP_URL = "http://${cfg.httpHost}:${toString cfg.httpPort}";
        GHIDRA_MCP_BRIDGE_HOST = cfg.mcpHost;
        GHIDRA_MCP_BRIDGE_PORT = toString cfg.mcpPort;
        GHIDRA_MCP_BRIDGE_TRANSPORT = "streamable-http";
        GHIDRA_MCP_STATE = toString stateDir;
      };
      StandardOutPath = "${logDir}/bridge.log";
      StandardErrorPath = "${logDir}/bridge.log";
      WorkingDirectory = toString stateDir;
    };
  };
}
